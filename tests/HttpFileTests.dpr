program HttpFileTests;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$APPTYPE CONSOLE}

uses
  SysUtils,
  MiniTest,
  Test_Lexer_Primitives,
  Test_Lexer_CommentKinds,
  Test_Lexer_RequestLineKinds,
  Test_Lexer_VariableAndHeaderKinds,
  Test_Lexer_FileRefAndScriptKinds,
  Test_Parser_Variables,
  Test_Parser_VariableReferences,
  Test_Parser_RequestLine,
  Test_Parser_Headers,
  Test_Parser_Body,
  Test_Parser_FileBody,
  Test_Parser_EndpointNames,
  Test_Parser_ScriptsRejected,
  Test_Parser_ErrorPositions,
  Test_Parser_ValidSample,
  Test_Function_Guid,
  Test_Function_RandomInt,
  Test_Function_Timestamp,
  Test_Function_DateTime,
  Test_Function_LocalDateTime,
  Test_Function_DotEnv,
  Test_Function_CustomRegistration,
  Test_Function_Arguments,
  Test_Function_UnknownFunction,
  Test_DateFormat_DayJs,
  Test_Reference_Matching,
  Test_Reference_ResponseHeaders,
  Test_Reference_ResponseBody,
  Test_Reference_RequestScope,
  Test_Reference_Unresolved,
  Test_Scripting_Objects,
  Test_Scripting_ErrorCases,
  Test_JsonWriter,
  Test_Generator_Registry,
  Test_Generator_Curl,
  Test_Generator_CurlBatch,
  Test_Generator_CurlVariables,
  Test_Generator_Postman;

begin
  if RunAllTests > 0 then
    Halt(1);
end.
