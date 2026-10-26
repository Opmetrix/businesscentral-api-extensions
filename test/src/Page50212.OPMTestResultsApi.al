#if TESTAPP
/// <summary>Read-only API page with the result of every test method for each run.</summary>
page 50212 "OPM Test Results API"
{
    PageType = API;
    APIPublisher = 'opmetrix';
    APIGroup = 'testing';
    APIVersion = 'v1.0';
    EntityName = 'testResult';
    EntitySetName = 'testResults';
    SourceTable = "OPM Test Result";
    ODataKeyFields = SystemId;
    Editable = false;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;
    Caption = 'testResults', Locked = true;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(id; Rec.SystemId) { Caption = 'id', Locked = true; }
                field(runEntryNo; Rec."Run Entry No.") { Caption = 'runEntryNo', Locked = true; }
                field(codeunitId; Rec."Codeunit ID") { Caption = 'codeunitId', Locked = true; }
                field(codeunitName; Rec."Codeunit Name") { Caption = 'codeunitName', Locked = true; }
                field(functionName; Rec."Function Name") { Caption = 'functionName', Locked = true; }
                field(result; Rec.Result) { Caption = 'result', Locked = true; }
                field(errorMessage; Rec."Error Message") { Caption = 'errorMessage', Locked = true; }
            }
        }
    }
}
#endif
