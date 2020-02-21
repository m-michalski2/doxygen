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
#include "arguments.h"

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
    std::vector<std::shared_ptr<Entry>> constructors;

    bool readonlyAttribute;
    std::vector<std::string> attribute;
    std::string attributeRaises;
    std::string defaultVal;

    std::vector<std::string> typeDef;

    std::vector<std::string> arguments;
    std::vector<std::string> operation;
    std::string operationRaises;
    std::string operationArgs;
};


// static const char* stateToString(int);
// #define YY_USER_ACTION {                        \
//     static char RuleNum[4];                     \
//     sprintf(RuleNum, "%d", yylineno);           \
//     fprintf(stderr, "%s: <%s>\n", RuleNum, stateToString(YYSTATE)); \
// }


#define IMPORT_FLEX_INTERFACE \
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner

void setEntryDoc(yyscan_t yyscanner, std::shared_ptr<Entry> entry);
std::string getCurrentScope(const std::vector<std::string>& scope);

void exitSubtree(yyscan_t yyscanner);
void enterSubtree(yyscan_t yyscanner, std::shared_ptr<Entry> newRoot);
void resetCurrentEntry(yyscan_t yyscanner);
std::string getArgType(std::string code);
std::string getArgName(std::string code);
std::string getArgList(std::vector<Argument> al);
void endDefinition(yyscan_t yyscanner);

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
%x ArgumentList

B  [ \t]
BB [ \t]*

IDENTIFIER [a-zA-Z_][a-zA-Z0-9_]*
ARGLIST \(.*\)
MLARGLIST \(.*\n.*\)
STRING \"([^\\\"]|\\.)*\"

NUMBER_TYPE ("unsigned")?("short"|"long"|"long long"|"float"|"double")
NON_NUMBER_TYPE ("any")|[a-zA-Z_][a-zA-Z0-9_]*
SIMPLE_TYPE ("const")?{NUMBER_TYPE}|{NON_NUMBER_TYPE}("[]"|"?")?

RAISES ("raises"){BB}\(.*\)

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

    "Constructor" {
        yy_push_state(Constructor, yyscanner);
    }

    {IDENTIFIER} {
        yyextra->extendedAttributes.push_back(yytext);
    }

    "," {
        // ext attr separator
    }
}

<Constructor>{
    "(" {
        yy_push_state(ArgumentList, yyscanner);
    }

    ")" {
        auto entry = std::make_shared<Entry>();
        entry->section = Entry::FUNCTION_SEC;
        entry->name = "Constructor";
        entry->type = "";
        entry->mtype = Method;
        for (auto arg: yyextra->arguments) {
            Argument argDef;
            argDef.type = getArgType(arg).c_str();
            argDef.name = getArgName(arg).c_str();
            entry->argList.push_back(argDef);
        }
        yyextra->arguments.clear();
        setEntryDoc(yyscanner, entry);
        yyextra->constructors.push_back(entry);
        yy_pop_state(yyscanner);
    }
}

<ArgumentList>{
    ")" {
        yyless(0);
        yy_pop_state(yyscanner);
    }

    [^,)]+ {
        std::string argument = yytext;
        Argument arg;
        arg.type = getArgType(argument).c_str();
        arg.name = getArgName(argument).c_str();
        yyextra->currentEntry->argList.push_back(arg);

        yyextra->arguments.push_back(argument);
    }

    "," {
        /* arguments separator */
    }
}

<Module>{
    {IDENTIFIER} {
        //Doxygen::docGroup.enterCompound(yyextra->fileName, yylineno, yytext);
        //auto entry = std::make_shared<Entry>();
        //entry->name = yytext;
        //yyextra->currentScope.push_back(yytext);
        //entry->type = "namespace";
        //entry->fileName = yyextra->fileName;
        //entry->section = Entry::NAMESPACE_SEC;
        //entry->lang = SrcLangExt_WebIDL;
        //yyextra->currentRoot->moveToSubEntryAndKeep(entry);
        //setEntryDoc(yyscanner, entry);
        //yyextra->currentRoot = entry;
        yyextra->currentRoot->name = yytext;
        yyextra->currentRoot->fileName = yyextra->fileName;
        yyextra->currentRoot->lang = SrcLangExt_WebIDL;
        yyextra->lastComment += std::string("\n\\file ") + yyextra->fileName;
        setEntryDoc(yyscanner, yyextra->currentRoot);
        yy_push_state(ModuleBody, yyscanner);
    }

    ";" {
        yy_pop_state(yyscanner);
        //yyextra->currentScope.pop_back();
        //Doxygen::docGroup.leaveCompound(yyextra->fileName, yylineno, yyextra->currentRoot->name);
        //yyextra->currentRoot = yyextra->parent;
        //endDefinition(yyscanner);
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
    {SIMPLE_TYPE} {
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
        setEntryDoc(yyscanner, entry);
        yyextra->typeDef.clear();
        yyextra->currentRoot->moveToSubEntryAndKeep(entry);
        endDefinition(yyscanner);
        yy_pop_state(yyscanner);
    }
}

<EnumDef>{
    {IDENTIFIER} {
        Doxygen::docGroup.enterCompound(yyextra->fileName, yylineno, yytext);
        yyextra->parent = yyextra->currentRoot;
        auto entry = std::make_shared<Entry>();
        entry->type = "enum";
        entry->fileName = yyextra->fileName;
        entry->name = yytext;
        entry->section = Entry::ENUM_SEC;
        entry->lang = SrcLangExt_WebIDL;
        entry->spec = Entry::Enum | Entry::Strong;

        setEntryDoc(yyscanner, entry);
        yyextra->currentRoot->moveToSubEntryAndKeep(entry);
        yyextra->currentRoot = entry;

    }

    ";" {
        yy_pop_state(yyscanner);
        Doxygen::docGroup.leaveCompound(yyextra->fileName, yylineno, yyextra->currentRoot->name);
        yyextra->currentRoot = yyextra->parent;
        endDefinition(yyscanner);
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
        setEntryDoc(yyscanner, ev);
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
        Doxygen::docGroup.enterCompound(yyextra->fileName, yylineno, yytext);
        yyextra->currentScope.push_back(yytext);
        std::string interfaceName = yyextra->currentScope.back();
        auto entry = std::make_shared<Entry>();
        entry->type = "interface";
        entry->fileName = yyextra->fileName;
        entry->name = interfaceName.c_str();
        entry->section = Entry::CLASS_SEC;
        entry->lang = SrcLangExt_WebIDL;
        entry->spec = Entry::Interface;
        entry->proto = TRUE;

        setEntryDoc(yyscanner, entry);
        yyextra->currentRoot->moveToSubEntryAndKeep(entry);
        yyextra->parent = yyextra->currentRoot;
        yyextra->currentRoot = entry;

        for (auto ctor: yyextra->constructors) {
            ctor->name = yyextra->currentRoot->name;
            setEntryDoc(yyscanner, ctor);
            yyextra->currentRoot->moveToSubEntryAndKeep(ctor);
        }

        yyextra->constructors.clear();
    }

    ":"{BB}{IDENTIFIER} {
        std::string name = yytext;
        auto beg = std::find_if(begin(name), end(name), (int(*)(int))std::isalnum);
        std::string baseInterface = std::string(beg, name.end());
        yyextra->currentRoot->extends.push_back(
            BaseInfo(baseInterface.c_str(), Public, Normal)
        );
    }

    "{" {
        yy_push_state(InterfaceBody, yyscanner);
    }

    ";" {
        yy_pop_state(yyscanner);
        yyextra->currentRoot = yyextra->parent;
        yyextra->currentScope.pop_back();
        yyextra->baseInterface.clear();
        Doxygen::docGroup.leaveCompound(yyextra->fileName, yylineno, yyextra->currentRoot->name);
        endDefinition(yyscanner);
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

    {SIMPLE_TYPE}|"(" {
        yyextra->currentEntry->section = Entry::FUNCTION_SEC;
        yyextra->currentEntry->type = yytext;
        yyextra->currentEntry->mtype = Method;
        yy_push_state(Operation, yyscanner);
    }
}

<Operation>{
    ";" {
        yyextra->currentEntry->args = getArgList(yyextra->currentEntry->argList).c_str();
        setEntryDoc(yyscanner, yyextra->currentEntry);
        yyextra->currentRoot->moveToSubEntryAndKeep(yyextra->currentEntry);
        yy_pop_state(yyscanner);
        endDefinition(yyscanner);
    }

    {RAISES} {
        yyextra->currentEntry->exception = yytext;
    }

    {IDENTIFIER}"(" {
        std::string s = yytext;
        yyextra->currentEntry->name = s.substr(0, s.size() - 1).c_str();
        yy_push_state(ArgumentList, yyscanner);
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

        yyextra->currentRoot->moveToSubEntryAndKeep(entry);

        yyextra->attribute.clear();
        yyextra->attributeRaises.clear();
        yyextra->readonlyAttribute = false;
        yyextra->lastComment.clear();
        yyextra->defaultVal.clear();
        yy_pop_state(yyscanner);
        endDefinition(yyscanner);
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
        std::shared_ptr<Entry> entry = std::make_shared<Entry>();
        entry->type = "dictionary";
        entry->fileName = yyextra->fileName;
        entry->name = yytext;
        entry->section = Entry::CLASS_SEC;
        entry->lang = SrcLangExt_WebIDL;
        entry->spec = Entry::Dictionary;
        entry->proto = TRUE;
        setEntryDoc(yyscanner, entry);
        yyextra->currentRoot->moveToSubEntryAndKeep(entry);
        yyextra->parent = yyextra->currentRoot;
        yyextra->currentRoot = entry;
    }

    ";" {
        yy_pop_state(yyscanner);
        endDefinition(yyscanner);
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


void setEntryDoc(yyscan_t yyscanner, std::shared_ptr<Entry> entry)
{
    IMPORT_FLEX_INTERFACE;
    auto protection = Public;
    int position = 0;
    bool needsEntry = false;
    yyextra->commentScanner.parseCommentBlock(
        yyextra->parser,
        entry.get(),
        yyextra->lastComment.c_str(),
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

std::string getArgName(std::string code) {
    int pos = code.rfind(" ");
    return code.substr(pos, code.size() - pos);
}

std::string getArgType(std::string code) {
    int pos = code.rfind(" ");
    return code.substr(0, pos);
}

std::string getArgList(std::vector<Argument> al) {
    std::string ret = "(";
    int alSize = al.size();
    for (int i = 0; i < alSize; i++) {
        ret += al[i].type + al[i].name;
        if (i < alSize - 1)
            ret += ", ";
    }
    return ret + ")";
}

void resetCurrentEntry(yyscan_t yyscanner) {
    IMPORT_FLEX_INTERFACE;
    yyextra->currentEntry = std::make_shared<Entry>();
    Doxygen::docGroup.initGroupInfo(yyextra->currentEntry.get());
}

void enterSubtree(yyscan_t yyscanner, std::shared_ptr<Entry> newRoot) {
    IMPORT_FLEX_INTERFACE;
    yyextra->currentRoot = newRoot;
}

void exitSubtree(yyscan_t yyscanner) {
    IMPORT_FLEX_INTERFACE;
    yyextra->currentRoot.reset(yyextra->currentRoot->parent());
}

void endDefinition(yyscan_t yyscanner) {
    IMPORT_FLEX_INTERFACE;
    yyextra->lastComment.clear();
    yyextra->extendedAttributes.clear();
    yyextra->constructors.clear();
    yyextra->baseInterface.clear();
    yyextra->readonlyAttribute = false;
    yyextra->attribute.clear();
    yyextra->attributeRaises.clear();
    yyextra->defaultVal.clear();
    yyextra->typeDef.clear();
    yyextra->arguments.clear();
    yyextra->operation.clear();
    yyextra->operationArgs.clear();
    yyextra->operationRaises.clear();
    resetCurrentEntry(yyscanner);
}


void WebIDLOutlineParser::parseInput(
    const char *fileName,
    const char *fileBuf,
    const std::shared_ptr<Entry> &root,
    bool,
    QStrList&)
{
    auto& yyscanner = p->yyscanner;
    IMPORT_FLEX_INTERFACE;
    printlex(1, TRUE, __FILE__, fileName);

    yyextra->parser = this;
    yyextra->fileName = fileName;
    yyextra->currentRoot = root;
    endDefinition(yyscanner);

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
