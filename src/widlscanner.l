%option stack
%option never-interactive
%option prefix="widlscannerYY"
%option reentrant
%option noyywrap
%option yylineno
%option extra-type="struct widlscannerYY_state *"

%{

#include <stdio.h>
#include <sstream>
#include <algorithm>
#include <cctype>

#include "message.h"
#include "entry.h"
#include "doxygen.h"
#include "commentscan.h"
#include "types.h"

#include "widlscanner.h"
#include "widlcode.h"

#define YY_NO_INPUT 1
#define YY_NO_UNISTD_H 1

struct widlscannerYY_state
{
    WebIDLOutlineParser* thisParser;
    CommentScanner commentScanner;

    const char* fileName;
    const char* inputString;
    int inputPosition;

    std::shared_ptr<Entry> currentRoot;
    std::string lastComment;

    std::vector<std::string> currentScope;
    std::vector<std::string> extendedAttributes;

    std::string baseInterface;
    std::string interfaceName;
    std::string interfaceDoc;

    std::vector<std::string> attribute;
};

std::shared_ptr<Entry> createModuleEntry(const char*, const char*);
std::shared_ptr<Entry> createNamespaceEntry(const char*, const char*);

static int yyread(yyscan_t yyscanner, char *buf, int max_size);
#undef YY_INPUT
#define YY_INPUT(buf, result, max_size) result = yyread(yyscanner, buf, max_size);

/* Uncomment YY_USER_ACTION to print start condition for each action */
char RuleNum[4];
void printCurrentState(yyscan_t yyscanner, const char* label);
//#define YY_USER_ACTION { sprintf(RuleNum, "%d", yylineno); printCurrentState(yyscanner, RuleNum); }

void visitDoxygen(yyscan_t yyscanner, std::string text);
void visitModule(yyscan_t yyscanner, std::string interfaceName);
void visitInterface(yyscan_t yyscanner, std::string interfaceName);
void visitTypedef(yyscan_t yyscanner, std::string aliasName);
void visitMethod(yyscan_t yyscanner, std::string methodName);
void visitAttribute(yyscan_t yyscanner, std::string attributeName);
void visitEnum(yyscan_t yyscanner, std::string enumName);
void visitExtAttributes(yyscan_t yyscanner);
void visitConstructor(yyscan_t yyscanner);

%}

%x Comment
%x Module
%x ModuleBody
%x InterfaceDef
%x InterfaceBody
%x ExtendedAttributes
%x Attribute

B  [ \t]
BB [ \t]*

IDENTIFIER [a-zA-Z_][a-zA-Z0-9_]*
ARGLIST \(.*\)

%%

<INITIAL>{
    module {
        yy_push_state(Module, yyscanner);
    }
}

<*>"/**" {
    yyextra->lastComment = "";
    yy_push_state(Comment, yyscanner);
}

<Comment>{
    ^[ ]+"*/" {
        yy_pop_state(yyscanner);
    }

    ^[ ]+"*" {
    }

    .|\n {
        yyextra->lastComment += yytext;
    }
}

<INITIAL,ModuleBody>"[" {
    yy_push_state(ExtendedAttributes, yyscanner);
    yyextra->extendedAttributes.clear();
}

<ExtendedAttributes>{
    "]" {
        yy_pop_state(yyscanner);
    }

    "NoInterfaceObject" {
        yyextra->extendedAttributes.push_back(yytext);
    }

    "Constructor"{BB}{ARGLIST} {
        yyextra->extendedAttributes.push_back(yytext);
    }

    {IDENTIFIER}{BB}"="{BB}{IDENTIFIER}{BB}{ARGLIST} {
        yyextra->extendedAttributes.push_back(yytext);
    }

    {IDENTIFIER}{BB}"="{BB}{ARGLIST} {
        yyextra->extendedAttributes.push_back(yytext);
    }

    {IDENTIFIER}{BB}{ARGLIST} {
        yyextra->extendedAttributes.push_back(yytext);
    }

    {IDENTIFIER} {
        yyextra->extendedAttributes.push_back(yytext);
    }

    "," {
        // ext attr separator
    }
}

<Module>{
    {IDENTIFIER} {
        visitModule(yyscanner, yytext);
        visitDoxygen(yyscanner, yyextra->lastComment);
        yyextra->currentScope.push_back(yytext);
        yy_push_state(ModuleBody, yyscanner);
    }

    ";" {
        yy_pop_state(yyscanner);
        yyextra->currentScope.pop_back();
        BEGIN(INITIAL);
    }
}

<ModuleBody>{
    "{" {
    }

    "}" {
        yy_pop_state(yyscanner);
    }

    interface {
        yy_push_state(InterfaceDef, yyscanner);
    }
}

<InterfaceDef>{
    {IDENTIFIER} {
        yyextra->interfaceDoc = yyextra->lastComment;
        yyextra->interfaceName = yytext;
        yyextra->currentScope.push_back(yytext);
    }

    ":"{BB}{IDENTIFIER} {
        std::string name = yytext;
        auto beg = std::find_if(begin(name), end(name), [](char c){ return std::isalnum(c); });
        yyextra->baseInterface = std::string(beg, name.end());
        fprintf(stderr, "[WIDL] base(%s) = %s\n", yyextra->interfaceName.c_str(),
            yyextra->baseInterface.c_str());
    }

    "{" {
        yy_push_state(InterfaceBody, yyscanner);
    }

    ";" {
        visitInterface(yyscanner, yyextra->interfaceName);
        visitDoxygen(yyscanner, yyextra->interfaceDoc);
        yy_pop_state(yyscanner);

        yyextra->currentScope.pop_back();
        yyextra->baseInterface.clear();
        yyextra->interfaceName.clear();
        yyextra->interfaceDoc.clear();
    }
}

<InterfaceBody>{
    "}" {
        yy_pop_state(yyscanner);
    }

    "attribute" {
        yy_push_state(Attribute, yyscanner);
    }
}

<Attribute>{
    ";" {
        yyextra->attribute.clear();
        yy_pop_state(yyscanner);
    }

    {IDENTIFIER} {
        yyextra->attribute.push_back(yytext);
    }
}

<*>. {
}

<*>\n {
}

<<EOF>> {
    yyterminate();
}

%%

static int yyread(yyscan_t yyscanner, char* buf, int max_size) {
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
    int c = 0;
    const char *p = yyextra->inputString + yyextra->inputPosition;
    while (c < max_size && *p) {
        *buf++ = *p++;
        c++;
    }
    yyextra->inputPosition += c;
    return c;
}

struct WebIDLOutlineParser::Private
{
    yyscan_t yyscanner;
    widlscannerYY_state state;
};

WebIDLOutlineParser::WebIDLOutlineParser()
    : p(std::make_unique<WebIDLOutlineParser::Private>())
{
    widlscannerYYlex_init_extra(&p->state, &p->yyscanner);
#ifdef FLEX_DEBUG
    widlscannerYYset_debug(1, p->yyscanner);
#endif
}

WebIDLOutlineParser::~WebIDLOutlineParser()
{
    widlscannerYYlex_destroy(p->yyscanner);
}


std::shared_ptr<Entry> createNamespaceEntry(
    const char* fileName,
    const char* name) {
    std::shared_ptr<Entry> entry = std::make_shared<Entry>();
    entry->type = "namespace";
    entry->fileName = fileName;
    entry->name = name;
    entry->section = Entry::NAMESPACE_SEC;
    entry->lang = SrcLangExt_WebIDL;
    return entry;
}

std::shared_ptr<Entry> createInterfaceEntry(
    const char* fileName,
    const char* name,
    const char* baseInterface) {
    std::shared_ptr<Entry> entry = std::make_shared<Entry>();
    entry->type = "interface";
    entry->fileName = fileName;
    entry->name = name;
    entry->section = Entry::CLASS_SEC;
    entry->lang = SrcLangExt_WebIDL;
    entry->spec = Entry::Interface;
    entry->extends.push_back(
        BaseInfo(QCString("Tizen::")+baseInterface, Public, Normal)
    );
    return entry;
}

void visitDoxygen(yyscan_t yyscanner, std::string text) {
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
    auto protection = Public;
    int position = 0;
    bool needsEntry = false;
    yyextra->commentScanner.parseCommentBlock(
        yyextra->thisParser,
        yyextra->currentRoot.get(),
        text.c_str(),
        yyextra->fileName,
        yylineno,
        false,
        false,
        false,
        protection,
        position,
        needsEntry);
}

std::string getCurrentScope(const std::vector<std::string>& scope) {
    std::ostringstream oss;
    for (auto s: scope) {
        oss << s << "::";
    }
    return oss.str();
}

void visitModule(yyscan_t yyscanner, std::string moduleName) {
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
    moduleName = getCurrentScope(yyextra->currentScope) + moduleName;
    auto entry = createNamespaceEntry(yyextra->fileName, moduleName.c_str());
    Doxygen::docGroup.initGroupInfo(entry.get());
    yyextra->currentRoot->moveToSubEntryAndKeep(entry);
    yyextra->currentRoot = entry;
}

void visitInterface(yyscan_t yyscanner, std::string interfaceName) {
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
    interfaceName = getCurrentScope(yyextra->currentScope);
    interfaceName.pop_back(); interfaceName.pop_back();
    auto entry = createInterfaceEntry(
        yyextra->fileName,
        interfaceName.c_str(),
        yyextra->baseInterface.c_str()
    );
    Doxygen::docGroup.initGroupInfo(entry.get());
    yyextra->currentRoot->moveToSubEntryAndKeep(entry);
    yyextra->currentRoot = entry;
}

void visitTypedef(yyscan_t yyscanner, std::string aliasName) {
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
}

void visitMethod(yyscan_t yyscanner, std::string methodName) {
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
}

void visitAttribute(yyscan_t yyscanner, std::string attributeName) {
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
}

void visitEnum(yyscan_t yyscanner, std::string enumName) {
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
}

void visitExtAttributes(yyscan_t yyscanner) {
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
}

void visitConstructor(yyscan_t yyscanner) {
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
}

void printCurrentState(yyscan_t yyscanner, const char* label) {
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
    static const char* stateNames[100];
#define STATE_ENTRY(StateName) stateNames[StateName] = #StateName;
    STATE_ENTRY(INITIAL);
    STATE_ENTRY(Comment);
    STATE_ENTRY(Module);
    STATE_ENTRY(ModuleBody);
    STATE_ENTRY(InterfaceDef);
    STATE_ENTRY(InterfaceBody);
    STATE_ENTRY(ExtendedAttributes);
    STATE_ENTRY(Attribute);
#undef STATE_ENTRY
    fprintf(stderr, "%s: <%s>\n", label, stateNames[YYSTATE]);
}

void WebIDLOutlineParser::parseInput(
    const char *fileName,
    const char *fileBuf,
    const std::shared_ptr<Entry> &root,
    bool,
    QStrList&)
{
    struct yyguts_t *yyg = (struct yyguts_t*)p->yyscanner;

    printlex(1, TRUE, __FILE__, fileName);

    fprintf(stderr, "[WIDL] parsing file %s\n", fileName);

    yyextra->thisParser = this;
    yyextra->fileName = fileName;
    yyextra->currentRoot = root;

    yyextra->inputPosition = 0;
    yyextra->inputString = fileBuf;

    Doxygen::docGroup.enterFile(fileName, 0);
    widlscannerYYlex(p->yyscanner);
    Doxygen::docGroup.leaveFile(fileName, yylineno);

    printlex(yy_flex_debug, FALSE, __FILE__, fileName);
}

bool WebIDLOutlineParser::needsPreprocessing(const QCString &) const
{
  return FALSE;
}

void WebIDLOutlineParser::parsePrototype(const char *text)
{
}


#include "widlscanner.l.h"
