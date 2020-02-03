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

    std::shared_ptr<Entry> currentRoot;
    std::shared_ptr<Entry> parent;

    std::string lastComment;

    std::vector<std::string> currentScope;
    std::vector<std::string> extendedAttributes;

    std::string baseInterface;
    std::string interfaceName;
    std::string interfaceDoc;
    std::vector<std::shared_ptr<Entry>> constructors;

    std::string enumName;
    std::string enumDoc;
    std::map<std::string, std::string> enumValues;

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

std::shared_ptr<Entry> createModuleEntry(const char*, const char*);
std::shared_ptr<Entry> createNamespaceEntry(const char*, const char*);

/*
void printCurrentState(yyscan_t yyscanner, const char* label);
#define YY_USER_ACTION {                        \
    static char RuleNum[4];                     \
    sprintf(RuleNum, "%d", yylineno);           \
    printCurrentState(yyscanner, RuleNum);      \
}
*/

void visitDoxygen(yyscan_t yyscanner, std::string text, std::shared_ptr<Entry> root = nullptr);
void visitModule(yyscan_t yyscanner, std::string interfaceName);
void visitInterface(yyscan_t yyscanner, std::string interfaceName);
void visitTypedef(yyscan_t yyscanner);
void visitOperation(yyscan_t yyscanner);
void visitEnum(yyscan_t yyscanner);
void visitDictionary(yyscan_t yyscanner);
void visitExtAttributes(yyscan_t yyscanner);
void visitConstructor(yyscan_t yyscanner);
void visitAttribute(yyscan_t yyscanner);
std::shared_ptr<Entry> createOperationEntry(yyscan_t yyscanner);

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
    yyextra->constructors.clear();
}

<ExtendedAttributes>{
    "]" {
        yy_pop_state(yyscanner);
    }

    "NoInterfaceObject" {
        fprintf(stderr, "[WIDL] NoINterfaceObject: %s\n", yytext);
        yyextra->extendedAttributes.push_back(yytext);
    }

    {IDENTIFIER}{BB}"="{BB}{IDENTIFIER}{BB}{ARGLIST} {
        fprintf(stderr, "[WIDL] EA Identifier: %s\n", yytext);
        yyextra->extendedAttributes.push_back(yytext);
    }

    {IDENTIFIER}{BB}"="{BB}{ARGLIST} {
        fprintf(stderr, "[WIDL] EA = ARG LIST: %s\n", yytext);
        yyextra->extendedAttributes.push_back(yytext);
    }

    {IDENTIFIER}{BB}{ARGLIST} {
        std::string text = yytext;
        int pos = text.rfind("Constructor", 0);
        if (pos == 0) {
            fprintf(stderr, "[WIDL] Constuctor: %s\n", yytext);
            yyextra->operation.push_back("Constructor");
            yyextra->operationArgs = text.substr(pos, text.size() - pos);
            auto entry = createOperationEntry(yyscanner);
            yyextra->constructors.push_back(entry);
        }
        else {
            yyextra->extendedAttributes.push_back(yytext);
            fprintf(stderr, "[WIDL] EA With ARGLIST 2: %s\n", yytext);
        }
    }

    {IDENTIFIER} {
        fprintf(stderr, "[WIDL] Identifier: %s\n", yytext);
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
    "raises"{BB}"("{BB}{IDENTIFIER}{BB}")" {
        yyextra->operationRaises = yytext;
    }

    ";" {
        visitOperation(yyscanner);
        yy_pop_state(yyscanner);
    }

    {ARGLIST} {
        // if (...) are encountered at the beginning of operation definition
        // they represent union type rather than argument list.
        if (yyextra->operation.empty()) {
            yyextra->operation.push_back(yytext);
        }
        else {
            yyextra->operationArgs = yytext;
        }
    }

    {IDENTIFIER}|"[]"|"?"|")"|"(" {
        yyextra->operation.push_back(yytext);
    }

}

<Attribute>{
    ";" {
        visitAttribute(yyscanner);
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
        visitDictionary(yyscanner);
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

std::shared_ptr<Entry> createDictionaryEntry(
    yyscan_t yyscanner,
    const char* fileName,
    std::string name,
    const char* baseInterface) {
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
    std::shared_ptr<Entry> entry = std::make_shared<Entry>();
    entry->type = "dictionary";
    entry->fileName = fileName;
    entry->name = name.c_str();
    entry->section = Entry::CLASS_SEC;
    entry->lang = SrcLangExt_WebIDL;
    entry->spec = Entry::Dictionary;
    entry->proto = TRUE;
    entry->extends.push_back(
        BaseInfo(QCString("Tizen::") + baseInterface, Public, Virtual)
    );
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

    // process extended attributes.
    for (auto ctor: yyextra->constructors) {
        fprintf(stderr, "adding constructor to %s\n", yyextra->currentRoot->name);
        ctor->name = yyextra->currentRoot->name;
        yyextra->currentRoot->moveToSubEntryAndKeep(ctor);
    }

    yyextra->constructors.clear();
}

void visitTypedef(yyscan_t yyscanner) {
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
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

std::shared_ptr<Entry> createOperationEntry(yyscan_t yyscanner) {
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
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
    visitDoxygen(yyscanner, yyextra->lastComment, entry);
    yyextra->operation.clear();
    yyextra->operationArgs.clear();
    yyextra->operationRaises.clear();
    return entry;
}

void visitOperation(yyscan_t yyscanner) {
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
    auto entry = createOperationEntry(yyscanner);
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
    entry->initializer = yyextra->defaultVal.c_str();
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

void visitDictionary(yyscan_t yyscanner) {
    struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
    auto entry = createDictionaryEntry(
        yyscanner,
        yyextra->fileName,
        getCurrentScope(yyextra->currentScope) + yyextra->dictName,
        yyextra->baseInterface.c_str()
    );
    visitDoxygen(yyscanner, yyextra->dictDoc, entry);
    Doxygen::docGroup.initGroupInfo(entry.get());
    yyextra->currentRoot->moveToSubEntryAndKeep(entry);
    yyextra->parent = yyextra->currentRoot;
    yyextra->currentRoot = entry;
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
    STATE_ENTRY(DictionaryDef);
    STATE_ENTRY(DictionaryBody);
    STATE_ENTRY(Operation);
    STATE_ENTRY(Constructor);
    STATE_ENTRY(Typedef);
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

    Doxygen::docGroup.enterFile(fileName, 0);

    auto lexBufState = widlscannerYY_scan_string(fileBuf, p->yyscanner);
    widlscannerYYlex(p->yyscanner);

    // TODO: this line causes SEGFAULT for some reason.
    //widlscannerYY_delete_buffer(lexBufState, p->yyscanner);

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
