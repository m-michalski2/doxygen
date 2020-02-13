%option stack
%option never-interactive
%option prefix="widlscannerYY"
%option reentrant
%option noyywrap
%option yylineno
%option extra-type="struct widlscannerYY_state *"
%option nounistd
%option noinput
%option nounput

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

struct widlscannerYY_state
{
    WebIDLOutlineParser* parser;
    CommentScanner commentScanner;

    const char* fileName;

    std::shared_ptr<Entry> currentRoot;
    std::shared_ptr<Entry> currentEntry;
    std::shared_ptr<Entry> parent;

    std::string lastComment;

    std::vector<std::string> currentScope;
    std::vector<std::string> extendedAttributes;

    std::string baseInterface;
    std::string interfaceName;
    std::vector<std::shared_ptr<Entry>> constructors;

    std::string dictName;
    std::string dictDoc;

    bool readonlyAttribute;
    std::vector<std::string> attribute;
    std::string attributeRaises;
    std::string defaultVal;

    std::vector<std::string> typeDef;

    std::vector<std::string> operation;
    std::string operationRaises;
    std::string operationArgs;
};

/*
#define YY_USER_ACTION {                        \
    static char RuleNum[4];                     \
    sprintf(RuleNum, "%d", yylineno);           \
    fprintf(stderr, "%s: <%s>\n", RuleNum, stateToString(YYSTATE)); \
}
*/


void setEntryDoc(yyscan_t yyscanner, std::string text, std::shared_ptr<Entry> entry);
std::string getCurrentScope(const std::vector<std::string>& scope);

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
%x DictionaryDef
%x DictionaryBody
%x Operation
%x Constructor

B  [ \t]
BB [ \t]*

IDENTIFIER [a-zA-Z_][a-zA-Z0-9_]*
ARGLIST \(.*\)
MLARGLIST \(.*\n.*\)
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

    {IDENTIFIER}{BB}"="{BB}{IDENTIFIER}{BB}{ARGLIST} {
        yyextra->extendedAttributes.push_back(yytext);
    }

    {IDENTIFIER}{BB}"="{BB}{ARGLIST} {
        yyextra->extendedAttributes.push_back(yytext);
    }

    {IDENTIFIER}{BB}{ARGLIST} {
        std::string text = yytext;
        int pos = text.rfind("Constructor", 0);
        if (pos == 0) {
            yyextra->operation.push_back("Constructor");
            yyextra->operationArgs = text.substr(pos + 11, text.size() - pos);

            auto entry = std::make_shared<Entry>();
            entry->section = Entry::FUNCTION_SEC;
            entry->name = yyextra->operation.back().c_str();
            entry->args = yyextra->operationArgs.c_str();
            entry->exception = yyextra->operationRaises.c_str();
            std::ostringstream returnType;
            for (size_t i=0; i<yyextra->operation.size() - 1; ++i) {
                returnType << yyextra->operation[i] << " ";
            }

            entry->type = returnType.str().c_str();
            entry->mtype = Method;
            setEntryDoc(yyscanner, yyextra->lastComment, entry);
            yyextra->operation.clear();
            yyextra->operationArgs.clear();
            yyextra->operationRaises.clear();

            yyextra->constructors.push_back(entry);
        }
        else {
            yyextra->extendedAttributes.push_back(yytext);
        }
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
        std::string moduleName = getCurrentScope(yyextra->currentScope) + yytext;
        auto entry = std::make_shared<Entry>();
        entry->type = "namespace";
        entry->fileName = yyextra->fileName;
        entry->name = moduleName.c_str();
        entry->section = Entry::NAMESPACE_SEC;
        entry->lang = SrcLangExt_WebIDL;
        yyextra->currentRoot->moveToSubEntryAndKeep(entry);
        setEntryDoc(yyscanner, yyextra->lastComment, entry);
        yyextra->currentRoot = entry;
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

    dictionary {
        yy_push_state(DictionaryDef, yyscanner);
    }
}

<Typedef>{
    {IDENTIFIER} {
        yyextra->typeDef.push_back(yytext);
    }

    "[]" {
        yyextra->typeDef.push_back(yytext);
    }

    "?" {
        yyextra->typeDef.push_back(yytext);
    }

    "("|")" {
        yyextra->typeDef.push_back(yytext);
    }

    ";" {
        auto entry = std::make_shared<Entry>();
        entry->section = Entry::VARIABLE_SEC;
        entry->name = yyextra->typeDef.back().c_str();
        entry->fileName = yyextra->fileName;
        entry->startLine = yylineno;
        entry->bodyLine = yylineno;
        QCString type = "typedef ";
        for (int i=0; i<yyextra->typeDef.size() - 1; ++i) {
            type += (yyextra->typeDef[i] + " ").c_str();
        }
        entry->type = type;
        setEntryDoc(yyscanner, yyextra->lastComment, entry);
        yyextra->typeDef.clear();
        yyextra->currentRoot->moveToSubEntryAndKeep(entry);
        yy_pop_state(yyscanner);
    }
}

<EnumDef>{
    {IDENTIFIER} {
        yyextra->parent = yyextra->currentRoot;
        auto entry = std::make_shared<Entry>();
        entry->type = "enum";
        entry->fileName = yyextra->fileName;
        entry->name = (getCurrentScope(yyextra->currentScope) + yytext).c_str();
        entry->section = Entry::ENUM_SEC;
        entry->lang = SrcLangExt_WebIDL;
        entry->spec = Entry::Enum | Entry::Strong;

        setEntryDoc(yyscanner, yyextra->lastComment, entry);
        yyextra->currentRoot->moveToSubEntryAndKeep(entry);
        yyextra->currentRoot = entry;

    }

    ";" {
        yy_pop_state(yyscanner);
        yyextra->currentRoot = yyextra->parent;
    }

    "{" {
        yy_push_state(EnumBody, yyscanner);
    }
}

<EnumBody>{
    {STRING} {
        auto ev = std::make_shared<Entry>();
        ev->type = "@";
        ev->fileName = yyextra->fileName;
        ev->section = Entry::VARIABLE_SEC;
        ev->lang = SrcLangExt_WebIDL;
        ev->spec = Entry::Value;
        ev->name = yytext;
        setEntryDoc(yyscanner, yyextra->lastComment, ev);
        yyextra->currentRoot->moveToSubEntryAndKeep(ev);
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
        yyextra->interfaceName = yytext;
        yyextra->currentScope.push_back(yytext);

        yyextra->interfaceName = getCurrentScope(yyextra->currentScope);
        yyextra->interfaceName.pop_back();
        yyextra->interfaceName.pop_back();

        auto entry = std::make_shared<Entry>();
        entry->type = "interface";
        entry->fileName = yyextra->fileName;
        entry->name = yyextra->interfaceName.c_str();
        entry->section = Entry::CLASS_SEC;
        entry->lang = SrcLangExt_WebIDL;
        entry->spec = Entry::Interface;
        entry->proto = TRUE;
        entry->extends.push_back(
            BaseInfo(QCString("Tizen::") + yyextra->baseInterface.c_str(), Public, Normal)
        );

        setEntryDoc(yyscanner, yyextra->lastComment, entry);
        yyextra->currentRoot->moveToSubEntryAndKeep(entry);
        yyextra->parent = yyextra->currentRoot;
        yyextra->currentRoot = entry;

        for (auto ctor: yyextra->constructors) {
            ctor->name = yyextra->currentRoot->name;
            //ctor->type = yyextra->currentRoot->name;
            setEntryDoc(yyscanner, yyextra->lastComment, ctor);
            yyextra->currentRoot->moveToSubEntryAndKeep(ctor);
        }

        yyextra->constructors.clear();
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

    {IDENTIFIER}|"(" {
        yyextra->operation.push_back(yytext);
        yy_push_state(Operation, yyscanner);
    }
}

<Constructor>{
    {ARGLIST} {
    }
}

<Operation>{
    ";" {
        auto entry = std::make_shared<Entry>();
        entry->section = Entry::FUNCTION_SEC;
        entry->name = yyextra->operation.back().c_str();
        entry->args = yyextra->operationArgs.c_str();
        entry->exception = yyextra->operationRaises.c_str();
        std::ostringstream returnType;
        for (size_t i=0; i<yyextra->operation.size() - 1; ++i) {
            returnType << yyextra->operation[i] << " ";
        }

        entry->type = returnType.str().c_str();
        entry->mtype = Method;
        setEntryDoc(yyscanner, yyextra->lastComment, entry);
        yyextra->operation.clear();
        yyextra->operationArgs.clear();
        yyextra->operationRaises.clear();

        yyextra->currentRoot->moveToSubEntryAndKeep(entry);

        yy_pop_state(yyscanner);
    }

    {IDENTIFIER}{BB}{ARGLIST}|{IDENTIFIER}{BB}{MLARGLIST} {
        std::string str = yytext;
        int argPos = str.find("(");
        yyextra->operation.push_back(str.substr(0, argPos));
        std::string args = str.substr(argPos, str.size() - argPos);
        if (std::string::npos == args.find("raises")) {
            yyextra->operationArgs = args;
        }
        else {
            int raisesPos = args.find("raises");
            yyextra->operationArgs = args.substr(0, raisesPos);
            yyextra->operationRaises = args.substr(raisesPos, args.size() - raisesPos);
        }
    }

    {IDENTIFIER}|"[]"|"?"|"("|")" {
        yyextra->operation.push_back(yytext);
    }
}

<Attribute>{
    ";" {
        auto entry = std::make_shared<Entry>();
        entry->section = Entry::VARIABLE_SEC;
        entry->name = yyextra->attribute.back().c_str();
        entry->protection = Public;
        entry->fileName = yyextra->fileName;
        entry->startLine = yylineno;
        entry->bodyLine = yylineno;
        entry->initializer = yyextra->defaultVal.c_str();
        entry->exception = yyextra->attributeRaises.c_str();

        std::ostringstream type;
        for (size_t i = 0; i < yyextra->attribute.size() - 1; ++i) {
            type << yyextra->attribute[i] << " ";
        }

        entry->type = type.str().c_str();
        if (yyextra->readonlyAttribute) {
            entry->spec = Entry::Property | Entry::Readonly;
        }

        setEntryDoc(yyscanner, yyextra->lastComment, entry);
        yyextra->currentRoot->moveToSubEntryAndKeep(entry);

        yyextra->attribute.clear();
        yyextra->attributeRaises.clear();
        yyextra->readonlyAttribute = false;
        yyextra->lastComment.clear();
        yyextra->defaultVal.clear();
        yy_pop_state(yyscanner);
    }

    {IDENTIFIER}|"[]"|"?"|"("|")" {
        yyextra->attribute.push_back(yytext);
    }

    "="[^;]+ {
        yyextra->defaultVal = yytext;
    }

    "raises"{BB}"("{BB}{IDENTIFIER}{BB}")" {
        yyextra->attributeRaises = yytext;
    }
}

<DictionaryDef>{
    {IDENTIFIER} {
        yyextra->dictName = yytext;
        yyextra->dictDoc = yyextra->lastComment;

        std::shared_ptr<Entry> entry = std::make_shared<Entry>();
        entry->type = "dictionary";
        entry->fileName = yyextra->fileName;
        entry->name = (getCurrentScope(yyextra->currentScope) + yyextra->dictName).c_str();
        entry->section = Entry::CLASS_SEC;
        entry->lang = SrcLangExt_WebIDL;
        entry->spec = Entry::Dictionary;
        entry->proto = TRUE;
        entry->extends.push_back(
            BaseInfo(QCString("Tizen::") + yyextra->baseInterface.c_str(), Public, Virtual)
        );

        setEntryDoc(yyscanner, yyextra->dictDoc, entry);
        yyextra->currentRoot->moveToSubEntryAndKeep(entry);
        yyextra->parent = yyextra->currentRoot;
        yyextra->currentRoot = entry;

        yyextra->lastComment.clear();
    }

    ";" {
        yy_pop_state(yyscanner);
        yyextra->dictName.clear();
        yyextra->dictDoc.clear();
    }

    "{" {
        yy_push_state(DictionaryBody, yyscanner);
    }

}

<DictionaryBody>{
    {IDENTIFIER}|"[]"|"?"|"("|")" {
        yyextra->attribute.push_back(yytext);
        yy_push_state(Attribute, yyscanner);
    }

    "}" {
        yy_pop_state(yyscanner);
    }
}

<*>. {
}

<*>\n {
}

%%

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


void setEntryDoc(yyscan_t yyscanner, std::string text, std::shared_ptr<Entry> entry)
{
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
    auto protection = Public;
    int position = 0;
    bool needsEntry = false;
    yyextra->commentScanner.parseCommentBlock(
        yyextra->parser,
        entry.get(),
        text.c_str(),
        yyextra->fileName,
        yylineno,
        false,
        false,
        false,
        protection,
        position,
        needsEntry);
    yyextra->lastComment.clear();
}

std::string getCurrentScope(const std::vector<std::string>& scope)
{
    std::ostringstream oss;
    for (auto s: scope) {
        oss << s << "::";
    }
    return oss.str();
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

    yyextra->parser = this;
    yyextra->fileName = fileName;
    yyextra->currentRoot = root;

    Doxygen::docGroup.enterFile(fileName, 0);

    auto lexBufState = widlscannerYY_scan_string(fileBuf, p->yyscanner);
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
