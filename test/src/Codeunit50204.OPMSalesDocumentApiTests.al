#if TESTAPP
/// <summary>
/// Tests for the sales header API page (page 50139) and the sales invoice line API part (page 50138, reached through
/// the sales invoice API page 50137).
/// The page actions are called directly on page variables. The page triggers (OnModifyRecord, OnFindRecord, OnAfterGetRecord)
/// are run by calling the real OData endpoint, so these tests need a container whose OData/API services are reachable from
/// the test runner.
/// NOTE: posting commits, so these tests cannot be rolled back. Run them on a disposable BC container.
/// </summary>
codeunit 50204 "OPM Sales Document API Tests"
{
    Subtype = Test;

    var
        Assert: Codeunit "Library Assert";
        LibrarySales: Codeunit "Library - Sales";
        LibraryGraphMgt: Codeunit "Library - Graph Mgt";

    [Test]
    procedure ReleaseActionReleasesOrder()
    var
        SalesHeader: Record "Sales Header";
        SalesHeaderApi: Page "Sales Header Extension";
        ActionContext: WebServiceActionContext;
    begin
        CreateOrder(SalesHeader);

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
        CreateOrder(SalesHeader);

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
        CreateOrder(SalesHeader);
        LibrarySales.ReleaseSalesDocument(SalesHeader);

        SalesHeaderApi.SetRecord(SalesHeader);
        SalesHeaderApi.Reopen(ActionContext);

        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
        SalesHeader.TestField(Status, SalesHeader.Status::Open);
    end;

    [Test]
    procedure PatchingEditableFieldIsAccepted()
    var
        SalesHeader: Record "Sales Header";
        ResponseText: Text;
    begin
        CreateOrder(SalesHeader);

        // PATCH runs the OnModifyRecord trigger; id and number are unchanged so no error is raised
        LibraryGraphMgt.PatchToWebService(
          SalesHeaderUrl(SalesHeader), '{"yourReference":"Opmetrix test ref"}', ResponseText);

        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
        Assert.AreEqual('Opmetrix test ref', SalesHeader."Your Reference", 'Your Reference');
    end;

    [Test]
    procedure PatchingNumberIsRejected()
    var
        SalesHeader: Record "Sales Header";
        ResponseText: Text;
    begin
        CreateOrder(SalesHeader);

        asserterror LibraryGraphMgt.PatchToWebService(SalesHeaderUrl(SalesHeader), '{"number":"CHANGED"}', ResponseText);

        Assert.ExpectedError('The number cannot be changed.');
    end;

    [Test]
    procedure InvoiceLinesOfUnpostedInvoiceExposeUnitCostFromSalesLine()
    var
        SalesHeader: Record "Sales Header";
        ResponseText: Text;
    begin
        LibrarySales.CreateSalesInvoice(SalesHeader);

        // OnFindRecord loads the lines, OnAfterGetRecord reads the unit cost from the open sales line
        LibraryGraphMgt.GetFromWebService(ResponseText, SalesInvoiceLinesUrl(SalesHeader.SystemId));

        Assert.IsTrue(StrPos(ResponseText, 'unitCost') > 0, 'The lines should expose unitCost');
    end;

    [Test]
    procedure InvoiceLinesOfPostedInvoiceExposeUnitCostFromInvoiceLine()
    var
        SalesHeader: Record "Sales Header";
        SalesInvoiceHeader: Record "Sales Invoice Header";
        ResponseText: Text;
    begin
        LibrarySales.CreateSalesInvoice(SalesHeader);
        SalesInvoiceHeader.Get(LibrarySales.PostSalesDocument(SalesHeader, false, true));

        // OnAfterGetRecord reads the unit cost from the posted sales invoice line
        LibraryGraphMgt.GetFromWebService(ResponseText, SalesInvoiceLinesUrl(SalesInvoiceHeader.SystemId));

        Assert.IsTrue(StrPos(ResponseText, 'unitCost') > 0, 'The lines should expose unitCost');
    end;

    local procedure CreateOrder(var SalesHeader: Record "Sales Header")
    var
        SalesLine: Record "Sales Line";
        Item: Record Item;
    begin
        LibrarySales.CreateSalesHeader(SalesHeader, SalesHeader."Document Type"::Order, LibrarySales.CreateCustomerNo());
        LibraryInventoryCreateItem(Item);
        LibrarySales.CreateSalesLine(SalesLine, SalesHeader, SalesLine.Type::Item, Item."No.", 1);
    end;

    local procedure LibraryInventoryCreateItem(var Item: Record Item)
    var
        LibraryInventory: Codeunit "Library - Inventory";
    begin
        LibraryInventory.CreateItem(Item);
    end;

    local procedure SalesHeaderUrl(SalesHeader: Record "Sales Header"): Text
    begin
        exit(
          GetUrl(ClientType::Api, CompanyName(), ObjectType::Page, Page::"Sales Header Extension") +
          '(' + GuidToKey(SalesHeader.SystemId) + ')');
    end;

    local procedure SalesInvoiceLinesUrl(InvoiceId: Guid): Text
    begin
        exit(
          GetUrl(ClientType::Api, CompanyName(), ObjectType::Page, Page::"Sales Invoice Extension") +
          '(' + GuidToKey(InvoiceId) + ')/salesInvoiceLines');
    end;

    local procedure GuidToKey(Id: Guid): Text
    begin
        exit(LowerCase(DelChr(Format(Id), '=', '{}')));
    end;
}
#endif
