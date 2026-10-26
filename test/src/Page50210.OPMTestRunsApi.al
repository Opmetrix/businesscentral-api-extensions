#if TESTAPP
/// <summary>API page to create a test run and start it with the "run" action. GET returns the totals of each run.</summary>
page 50210 "OPM Test Runs API"
{
    PageType = API;
    APIPublisher = 'opmetrix';
    APIGroup = 'testing';
    APIVersion = 'v1.0';
    EntityName = 'testRun';
    EntitySetName = 'testRuns';
    SourceTable = "OPM Test Run";
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    Caption = 'testRuns', Locked = true;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(id; Rec.SystemId) { Caption = 'id', Locked = true; Editable = false; }
                field(entryNo; Rec."Entry No.") { Caption = 'entryNo', Locked = true; Editable = false; }
                field(status; Rec.Status) { Caption = 'status', Locked = true; Editable = false; }
                field(startedAt; Rec."Started At") { Caption = 'startedAt', Locked = true; Editable = false; }
                field(finishedAt; Rec."Finished At") { Caption = 'finishedAt', Locked = true; Editable = false; }
                field(testsTotal; Rec."Tests Total") { Caption = 'testsTotal', Locked = true; Editable = false; }
                field(testsPassed; Rec."Tests Passed") { Caption = 'testsPassed', Locked = true; Editable = false; }
                field(testsFailed; Rec."Tests Failed") { Caption = 'testsFailed', Locked = true; Editable = false; }
                field(linesTotal; Rec."Lines Total") { Caption = 'linesTotal', Locked = true; Editable = false; }
                field(linesCovered; Rec."Lines Covered") { Caption = 'linesCovered', Locked = true; Editable = false; }
                field(coveragePct; Rec."Coverage Pct") { Caption = 'coveragePct', Locked = true; Editable = false; }
                field(message; Rec.Message) { Caption = 'message', Locked = true; }
                field(waitForExercise; Rec."Wait For Exercise") { Caption = 'waitForExercise', Locked = true; }
            }
        }
    }

    [ServiceEnabled]
    procedure exerciseDone(var ActionContext: WebServiceActionContext)
    begin
        Rec."Exercise Done" := true;
        Rec.Modify();
        Commit();

        ActionContext.SetObjectType(ObjectType::Page);
        ActionContext.SetObjectId(Page::"OPM Test Runs API");
        ActionContext.AddEntityKey(Rec.FieldNo(SystemId), Rec.SystemId);
        ActionContext.SetResultCode(WebServiceActionResultCode::Updated);
    end;

    [ServiceEnabled]
    procedure run(var ActionContext: WebServiceActionContext)
    var
        TestRun: Record "OPM Test Run";
    begin
        TestRun := Rec;
        Commit();
        if not Codeunit.Run(Codeunit::"OPM Coverage Runner", TestRun) then begin
            TestRun.Get(Rec."Entry No.");
            TestRun.Status := 'Failed';
            TestRun."Finished At" := CurrentDateTime();
            TestRun.Message := CopyStr(GetLastErrorText(), 1, MaxStrLen(TestRun.Message));
            TestRun.Modify();
        end;
        Rec.Get(Rec."Entry No.");

        ActionContext.SetObjectType(ObjectType::Page);
        ActionContext.SetObjectId(Page::"OPM Test Runs API");
        ActionContext.AddEntityKey(Rec.FieldNo(SystemId), Rec.SystemId);
        ActionContext.SetResultCode(WebServiceActionResultCode::Updated);
    end;
}
#endif
