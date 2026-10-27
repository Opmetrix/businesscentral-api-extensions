#if TESTAPP
/// <summary>
/// Runs every test of this app with Microsoft's test runner inside the current session, tracks code coverage of the
/// Opmetrix extension objects (50100 to 50149) and stores the results in the OPM tables so they can be read through the API.
/// </summary>
codeunit 50210 "OPM Coverage Runner"
{
    TableNo = "OPM Test Run";
    Permissions = tabledata "OPM Test Run" = rimd,
                  tabledata "OPM Coverage Line" = rimd,
                  tabledata "OPM Test Result" = rimd;

    var
        SuiteNameTxt: Label 'OPMCOV', Locked = true;
        FirstExtensionObjectId: Integer;
        LastExtensionObjectId: Integer;

    trigger OnRun()
    begin
        Execute(Rec);
    end;

    local procedure Execute(var TestRun: Record "OPM Test Run")
    var
        ALTestSuite: Record "AL Test Suite";
        TestMethodLine: Record "Test Method Line";
        TestSuiteMgt: Codeunit "Test Suite Mgt.";
        ModuleInfo: ModuleInfo;
        SuiteName: Code[10];
    begin
        FirstExtensionObjectId := 50100;
        LastExtensionObjectId := 50149;

        TestRun.Status := 'Running';
        TestRun."Started At" := CurrentDateTime();
        TestRun.Modify();
        Commit();

        NavApp.GetCurrentModuleInfo(ModuleInfo);
        SuiteName := SuiteNameTxt;
        if ALTestSuite.Get(SuiteName) then
            ALTestSuite.Delete(true);
        TestSuiteMgt.CreateTestSuite(SuiteName);
        ALTestSuite.Get(SuiteName);
        // The code under test commits, so the runner must not use test isolation
        TestSuiteMgt.ChangeTestRunner(ALTestSuite, Codeunit::"Test Runner - Isol. Disabled");
        TestSuiteMgt.SelectTestMethodsByExtension(ALTestSuite, Format(ModuleInfo.Id));
        Commit();

        // With "Wait For Exercise" the run tracks all sessions and waits until the caller says it has finished calling the
        // extension's OData endpoints, so page triggers that only run over OData are counted as well
        StartCoverage(TestRun."Wait For Exercise");
        if TestRun."Wait For Exercise" then
            WaitForExercise(TestRun);
        TestMethodLine."Test Suite" := SuiteName;
        TestSuiteMgt.RunAllTests(TestMethodLine);
        StopCoverage(TestRun."Wait For Exercise");

        StoreTestResults(TestRun, SuiteName);
        StoreCoverage(TestRun);

        TestRun.Status := 'Finished';
        TestRun."Finished At" := CurrentDateTime();
        TestRun.Modify();
    end;

    local procedure WaitForExercise(var TestRun: Record "OPM Test Run")
    var
        Current: Record "OPM Test Run";
        Waited: Integer;
    begin
        TestRun.Status := 'Waiting';
        TestRun.Modify();
        Commit();
        repeat
            Sleep(1000);
            Waited += 1;
            Current.Get(TestRun."Entry No.");
        until Current."Exercise Done" or (Waited >= 600);
        // The caller changed the record in another session, so take its current version before updating it again
        TestRun.Get(TestRun."Entry No.");
    end;

    local procedure StartCoverage(AllSessions: Boolean)
    var
        AllObj: Record AllObj;
    begin
        // Only the extension's codeunits, pages and queries are tracked
        AllObj.SetFilter("Object Type", '%1|%2|%3', AllObj."Object Type"::Codeunit, AllObj."Object Type"::Page, AllObj."Object Type"::Query);
        AllObj.SetRange("Object ID", FirstExtensionObjectId, LastExtensionObjectId);
        CodeCoverageInclude(AllObj);
        CodeCoverageLog(true, AllSessions);
    end;

    local procedure StopCoverage(AllSessions: Boolean)
    begin
        CodeCoverageRefresh();
        CodeCoverageLog(false, AllSessions);
    end;

    local procedure StoreTestResults(var TestRun: Record "OPM Test Run"; SuiteName: Code[10])
    var
        TestMethodLine: Record "Test Method Line";
        TestResult: Record "OPM Test Result";
        CodeunitName: Text[50];
        CodeunitId: Integer;
    begin
        TestMethodLine.SetRange("Test Suite", SuiteName);
        if not TestMethodLine.FindSet() then
            exit;
        repeat
            if TestMethodLine."Line Type" = TestMethodLine."Line Type"::Codeunit then begin
                CodeunitId := TestMethodLine."Test Codeunit";
                CodeunitName := CopyStr(TestMethodLine.Name, 1, MaxStrLen(CodeunitName));
            end;
            if TestMethodLine."Line Type" = TestMethodLine."Line Type"::"Function" then begin
                TestResult.Init();
                TestResult."Entry No." := 0;
                TestResult."Run Entry No." := TestRun."Entry No.";
                TestResult."Codeunit ID" := CodeunitId;
                TestResult."Codeunit Name" := CodeunitName;
                TestResult."Function Name" := CopyStr(TestMethodLine.Function, 1, MaxStrLen(TestResult."Function Name"));
                TestResult.Result := CopyStr(Format(TestMethodLine.Result), 1, MaxStrLen(TestResult.Result));
                TestResult."Error Message" := CopyStr(TestMethodLine."Error Message Preview", 1, MaxStrLen(TestResult."Error Message"));
                TestResult.Insert();

                TestRun."Tests Total" += 1;
                if TestMethodLine.Result = TestMethodLine.Result::Success then
                    TestRun."Tests Passed" += 1;
                if TestMethodLine.Result = TestMethodLine.Result::Failure then
                    TestRun."Tests Failed" += 1;
            end;
        until TestMethodLine.Next() = 0;
    end;

    local procedure StoreCoverage(var TestRun: Record "OPM Test Run")
    var
        CodeCoverage: Record "Code Coverage";
        CoverageLine: Record "OPM Coverage Line";
    begin
        CodeCoverage.SetRange("Line Type", CodeCoverage."Line Type"::Code);
        CodeCoverage.SetRange("Object ID", FirstExtensionObjectId, LastExtensionObjectId);
        if CodeCoverage.FindSet() then
            repeat
                CoverageLine.Init();
                CoverageLine."Entry No." := 0;
                CoverageLine."Run Entry No." := TestRun."Entry No.";
                CoverageLine."Object Type" := CopyStr(Format(CodeCoverage."Object Type"), 1, MaxStrLen(CoverageLine."Object Type"));
                CoverageLine."Object ID" := CodeCoverage."Object ID";
                CoverageLine."Line No." := CodeCoverage."Line No.";
                CoverageLine."Line Text" := CopyStr(CodeCoverage.Line, 1, MaxStrLen(CoverageLine."Line Text"));
                CoverageLine.Hits := CodeCoverage."No. of Hits";
                CoverageLine.Insert();

                TestRun."Lines Total" += 1;
                if CodeCoverage."No. of Hits" > 0 then
                    TestRun."Lines Covered" += 1;
            until CodeCoverage.Next() = 0;

        if TestRun."Lines Total" > 0 then
            TestRun."Coverage Pct" := Round(TestRun."Lines Covered" / TestRun."Lines Total" * 100, 0.01);
    end;
}
#endif
