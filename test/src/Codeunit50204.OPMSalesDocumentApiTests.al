#if TESTAPP
/// <summary>
/// Tests for the actions of the sales header API page (page 50139). The actions are called directly on a page variable.
/// The page triggers (OnModifyRecord) and the sales invoice line part (page 50138) only run when served over OData, so they are
/// exercised by Measure-Coverage.ps1 while coverage tracking is on.
/// </summary>
codeunit 50204 "OPM Sales Document API Tests"
{
    Subtype = Test;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "OPM Test Helper";

    [Test]
    procedure ReleaseActionReleasesOrder()
    var
        SalesHeader: Record "Sales Header";
        SalesHeaderApi: Page "Sales Header Extension";
        ActionContext: WebServiceActionContext;
    begin
        Helper.CreateOrder(SalesHeader, 1, false);

        SalesHeaderApi.SetRecord(SalesHeader);
        SalesHeaderApi.Release(ActionContext);

        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
        SalesHeader.TestField(Status, SalesHeader.Status::Released);
    end;

    [Test]
    procedure CheckAndReleaseActionReleasesOrder()
    var
        SalesHeader: Record "Sales Header";
        SalesHeaderApi: Page "Sales Header Extension";
        ActionContext: WebServiceActionContext;
    begin
        Helper.CreateOrder(SalesHeader, 1, false);

        SalesHeaderApi.SetRecord(SalesHeader);
        SalesHeaderApi.CheckAndRelease(ActionContext);

        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
        SalesHeader.TestField(Status, SalesHeader.Status::Released);
    end;

    [Test]
    procedure ReopenActionReopensReleasedOrder()
    var
        SalesHeader: Record "Sales Header";
        SalesHeaderApi: Page "Sales Header Extension";
        ActionContext: WebServiceActionContext;
    begin
        Helper.CreateOrder(SalesHeader, 1, false);
        Helper.ReleaseOrder(SalesHeader);

        SalesHeaderApi.SetRecord(SalesHeader);
        SalesHeaderApi.Reopen(ActionContext);

        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
        SalesHeader.TestField(Status, SalesHeader.Status::Open);
    end;
}
#endif
