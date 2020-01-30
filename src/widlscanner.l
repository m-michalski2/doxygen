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
    std::shared_ptr<Entry> parent;

    std::string lastComment;

    std::vector<std::string> currentScope;
    std::vector<std::string> extendedAttributes;

    std::string baseInterface;
    std::string interfaceName;
    std::string interfaceDoc;

    std::string enumName;
    std::string enumDoc;
    std::map<std::string, std::string> enumValues;

    bool readonlyAttribute;
    std::vector<std::string> attribute;
    std::string attributeRaises;

    std::vector<std::string> typeDef;

    std::string operationName;
    std::string returnType;
    std::string operationRaises;
    std::string operationArgs;
};

std::shared_ptr<Entry> createModuleEntry(const char*, const char*);
std::shared_ptr<Entry> createNamespaceEntry(const char*, const char*);

static int yyread(yyscan_t yyscanner, char *buf, int max_size);
#undef YY_INPUT
#define YY_INPUT(buf, result, max_size) result = yyread(yyscanner, buf, max_size);

void printCurrentState(yyscan_t yyscanner, const char* label);
//#define YY_USER_ACTION {                      \
    static char RuleNum[4];                     \
    sprintf(RuleNum, "%d", yylineno);           \
    printCurrentState(yyscanner, RuleNum);      \
}

void visitDoxygen(yyscan_t yyscanner, std::string text, std::shared_ptr<Entry> root = nullptr);
void visitModule(yyscan_t yyscanner, std::string interfaceName);
void visitInterface(yyscan_t yyscanner, std::string interfaceName);
void visitTypedef(yyscan_t yyscanner);
void visitOperation(yyscan_t yyscanner);
void visitEnum(yyscan_t yyscanner);
void visitExtAttributes(yyscan_t yyscanner);
void visitConstructor(yyscan_t yyscanner);
void visitAttribute(yyscan_t yyscanner);

%}

%x Comment
%x Module
%x ModuleBody
%x InterfaceDef
%x InterfaceBody
%x EnumDef
%x EnumBody
%x Typedef
%x ExtendedAttributes
%x Attribute
%x Operation

B  [ \t]
BB [ \t]*

IDENTIFIER [a-zA-Z_][a-zA-Z0-9_]*
ARGLIST \(.*\)
STRING \"([^\\\"]|\\.)*\"

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

    enum {
        yy_push_state(EnumDef, yyscanner);
    }

    typedef {
        yy_push_state(Typedef, yyscanner);
    }
}

<Typedef>{
    {IDENTIFIER} {
        yyextra->typeDef.push_back(yytext);
    }

    ";" {
        visitTypedef(yyscanner);
        yy_pop_state(yyscanner);
    }
}

<EnumDef>{
    {IDENTIFIER} {
        yyextra->enumName = yytext;
        yyextra->enumDoc = yyextra->lastComment;
    }

    ";" {
        visitEnum(yyscanner);
        yy_pop_state(yyscanner);

        yyextra->enumName.clear();
        yyextra->enumValues.clear();
        yyextra->enumDoc.clear();

    }

    "{" {
        yy_push_state(EnumBody, yyscanner);
    }
}

<EnumBody>{
    {STRING} {
        yyextra->enumValues[yytext] = yyextra->lastComment;
    }

    "," {
        /* enum values separator */
    }

    "}" {
        yy_pop_state(yyscanner);
    }
}

<InterfaceDef>{
    {IDENTIFIER} {
        yyextra->interfaceDoc = yyextra->lastComment;
        yyextra->interfaceName = yytext;
        yyextra->currentScope.push_back(yytext);
        visitInterface(yyscanner, yyextra->interfaceName);
    }

    ":"{BB}{IDENTIFIER} {
        std::string name = yytext;
        auto beg = std::find_if(begin(name), end(name), (int(*)(int))std::isalnum);
        yyextra->baseInterface = std::string(beg, name.end());
    }

    "{" {
        yy_push_state(InterfaceBody, yyscanner);
    }

    ";" {
        yy_pop_state(yyscanner);
        yyextra->currentRoot = yyextra->parent;
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

    "readonly attribute" {
        yyextra->readonlyAttribute = true;
        yy_push_state(Attribute, yyscanner);
    }

    "attribute" {
        yyextra->readonlyAttribute = false;
        yy_push_state(Attribute, yyscanner);
    }

    {IDENTIFIER} {
        yyextra->returnType = yytext;
        yy_push_state(Operation, yyscanner);
    }
}

<Operation>{
    {IDENTIFIER} {
        yyextra->operationName = yytext;
    }

    {ARGLIST} {
        yyextra->operationArgs = yytext;
    }

    "raises"{BB}"("{BB}{IDENTIFIER}{BB}")" {
        yyextra->operationRaises = yytext;
    }

    ";" {
        visitOperation(yyscanner);
        yy_pop_state(yyscanner);
    }
}

<Attribute>{
    ";" {
        visitAttribute(yyscanner);
        yyextra->attribute.clear();
        yyextra->attributeRaises.clear();
        yyextra->readonlyAttribute = false;
        yy_pop_state(yyscanner);
    }

    {IDENTIFIER} {
        yyextra->attribute.push_back(yytext);
    }

    "raises"{BB}"("{BB}{IDENTIFIER}{BB}")" {
        yyextra->attributeRaises = yytext;
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
    entry->proto = TRUE;
    entry->extends.push_back(
        BaseInfo(QCString("Tizen::") + baseInterface, Public, Normal)
    );
    return entry;
}

std::shared_ptr<Entry> createEnumEntry(
    yyscan_t yyscanner,
    const char* fileName,
    std::string name,
    std::map<std::string, std::string> values) {
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
    std::shared_ptr<Entry> entry = std::make_shared<Entry>();
    entry->type = "enum";
    entry->fileName = fileName;
    entry->name = name.c_str();
    entry->section = Entry::ENUM_SEC;
    entry->lang = SrcLangExt_WebIDL;
    entry->spec = Entry::Enum | Entry::Strong;
    for (auto value: values) {
        auto ev = std::make_shared<Entry>();
        ev->type = "@";
        ev->fileName = fileName;
        ev->section = Entry::VARIABLE_SEC;
        ev->lang = SrcLangExt_WebIDL;
        ev->spec = Entry::Value;
        ev->name = value.first.c_str();
        visitDoxygen(yyscanner, value.second, ev);
        entry->moveToSubEntryAndKeep(ev);
    }
    return entry;
}

void visitDoxygen(yyscan_t yyscanner, std::string text, std::shared_ptr<Entry> root) {
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
    if (root == nullptr) root = yyextra->currentRoot;
    auto protection = Public;
    int position = 0;
    bool needsEntry = false;
    yyextra->commentScanner.parseCommentBlock(
        yyextra->thisParser,
        root.get(),
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
    visitDoxygen(yyscanner, yyextra->interfaceDoc, entry);
    yyextra->currentRoot->moveToSubEntryAndKeep(entry);
    yyextra->parent = yyextra->currentRoot;
    yyextra->currentRoot = entry;
}

void visitTypedef(yyscan_t yyscanner) {
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
    fprintf(stderr, "[WIDL] typedef: %s\n", yyextra->typeDef.back().c_str());
    auto entry = std::make_shared<Entry>();
    entry->section = Entry::VARIABLE_SEC;
    entry->name = yyextra->typeDef.back().c_str();
    entry->spec = Entry::Alias;
    entry->fileName = yyextra->fileName;
    entry->startLine = yylineno;
    entry->bodyLine = yylineno;
    QCString type = "typedef ";
    for (int i=0; i<yyextra->typeDef.size() - 1; ++i) {
        type += (yyextra->typeDef[i] + " ").c_str();
    }
    entry->type = type;
    visitDoxygen(yyscanner, yyextra->lastComment, entry);
    yyextra->currentRoot->moveToSubEntryAndKeep(entry);
}

void visitOperation(yyscan_t yyscanner) {
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
    auto entry = std::make_shared<Entry>();
    entry->section = Entry::FUNCTION_SEC;
    entry->name = yyextra->operationName.c_str();
    entry->args = yyextra->operationArgs.c_str();
    
    entry->exception = yyextra->operationRaises.c_str();
    entry->type = yyextra->returnType.c_str();
    entry->mtype = Method;
    visitDoxygen(yyscanner, yyextra->lastComment, entry);
    yyextra->currentRoot->moveToSubEntryAndKeep(entry);
}

void visitAttribute(yyscan_t yyscanner) {
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
    auto entry = std::make_shared<Entry>();
    entry->section = Entry::VARIABLE_SEC;
    entry->name = yyextra->attribute.back().c_str();
    entry->protection = Public;
    entry->fileName = yyextra->fileName;
    entry->startLine = yylineno;
    entry->bodyLine = yylineno;
    std::ostringstream type;
    for (size_t i = 0; i < yyextra->attribute.size() - 1; ++i) {
        type << yyextra->attribute[i] << " ";
    }
    entry->type = type.str().c_str();
    if (yyextra->readonlyAttribute) {
        entry->spec = Entry::Property | Entry::Readonly;
    }
    entry->exception = yyextra->attributeRaises.c_str();
    visitDoxygen(yyscanner, yyextra->lastComment, entry);
    yyextra->currentRoot->moveToSubEntryAndKeep(entry);
}

void visitEnum(yyscan_t yyscanner) {
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
    auto entry = createEnumEntry(
        yyscanner,
        yyextra->fileName,
        getCurrentScope(yyextra->currentScope) + yyextra->enumName,
        yyextra->enumValues
    );
    visitDoxygen(yyscanner, yyextra->enumDoc, entry);
    Doxygen::docGroup.initGroupInfo(entry.get());
    yyextra->currentRoot->moveToSubEntryAndKeep(entry);
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
    STATE_ENTRY(EnumDef);
    STATE_ENTRY(EnumBody);
    STATE_ENTRY(ExtendedAttributes);
    STATE_ENTRY(Attribute);
    STATE_ENTRY(Operation);
#undef STATE_ENTRY
    fprintf(stderr, "%s: <%s>\n", label, stateNames[YYSTATE]);
}

void WebIDLOutlineParser::parseInput(
    const char *fileName,
    const char *fileBuf,
    const std::shared_ptr<Entry> &root,
    bool,
    QStrList&){
    struct yyguts_t *yyg = (struct yyguts_t*)p->yyscanner;
    printlex(1, TRUE, __FILE__, fileName);

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
