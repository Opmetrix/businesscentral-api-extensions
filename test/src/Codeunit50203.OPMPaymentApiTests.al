/// <summary>
/// Tests for the customer payment journal API page (page 50128) and the customer payments API page (page 50129).
/// The page actions are called directly on page variables. The page triggers (OnOpenPage, OnNewRecord) are run by calling the
/// real OData endpoint, so these tests need a container whose OData/API services are reachable from the test runner.
/// NOTE: posting commits, so these tests cannot be rolled back. Run them on a disposable BC container.
/// </summary>
codeunit 50203 "OPM Payment API Tests"
{
    Subtype = Test;

    var
        Assert: Codeunit "Library Assert";
        LibraryERM: Codeunit "Library - ERM";
        LibrarySales: Codeunit "Library - Sales";
        LibraryRandom: Codeunit "Library - Random";
        LibraryGraphMgt: Codeunit "Library - Graph Mgt";
        LibraryUtility: Codeunit "Library - Utility";

    [Test]
    [HandlerFunctions('ConfirmHandlerYes,MessageHandler')]
    procedure PostCustomerPaymentJournalPostsAllLinesInBatch()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        CustLedgerEntry: Record "Cust. Ledger Entry";
        PaymentJournals: Page "APIV1 - Cust. Paym. Journals";
        ActionContext: WebServiceActionContext;
        CustomerNo: Code[20];
    begin
        CustomerNo := LibrarySales.CreateCustomerNo();
        CreatePaymentLine(GenJournalBatch, GenJournalLine, CustomerNo);

        PaymentJournals.SetRecord(GenJournalBatch);
        PaymentJournals.post(ActionContext);

        CustLedgerEntry.SetRange("Customer No.", CustomerNo);
        CustLedgerEntry.SetRange("Document Type", CustLedgerEntry."Document Type"::Payment);
        Assert.RecordIsNotEmpty(CustLedgerEntry);
        GenJournalLine.SetRange("Journal Template Name", GenJournalBatch."Journal Template Name");
        GenJournalLine.SetRange("Journal Batch Name", GenJournalBatch.Name);
        Assert.RecordIsEmpty(GenJournalLine);
    end;

    [Test]
    procedure PostCustomerPaymentJournalWithNoLinesIsRejected()
    var
        GenJournalTemplate: Record "Gen. Journal Template";
        GenJournalBatch: Record "Gen. Journal Batch";
        PaymentJournals: Page "APIV1 - Cust. Paym. Journals";
        ActionContext: WebServiceActionContext;
    begin
        LibraryERM.CreateGenJournalTemplate(GenJournalTemplate);
        LibraryERM.CreateGenJournalBatch(GenJournalBatch, GenJournalTemplate.Name);

        PaymentJournals.SetRecord(GenJournalBatch);
        asserterror PaymentJournals.post(ActionContext);

        Assert.ExpectedError('There is nothing to post.');
    end;

    [Test]
    procedure PostCustomerPaymentJournalForUnknownBatchIsRejected()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        PaymentJournals: Page "APIV1 - Cust. Paym. Journals";
        ActionContext: WebServiceActionContext;
    begin
        // A batch that was never inserted has a SystemId that does not exist in the database
        GenJournalBatch.Init();
        GenJournalBatch.SystemId := CreateGuid();

        PaymentJournals.SetRecord(GenJournalBatch);
        asserterror PaymentJournals.post(ActionContext);

        Assert.ExpectedError('cannot be found');
    end;

    [Test]
    [HandlerFunctions('ConfirmHandlerYes,MessageHandler')]
    procedure PostCustomerPaymentPostsJournalLine()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        CustLedgerEntry: Record "Cust. Ledger Entry";
        CustomerPayments: Page CustomerPayments;
        ActionContext: WebServiceActionContext;
        CustomerNo: Code[20];
    begin
        CustomerNo := LibrarySales.CreateCustomerNo();
        CreatePaymentLine(GenJournalBatch, GenJournalLine, CustomerNo);

        CustomerPayments.SetRecord(GenJournalLine);
        CustomerPayments.post(ActionContext);

        CustLedgerEntry.SetRange("Customer No.", CustomerNo);
        CustLedgerEntry.SetRange("Document Type", CustLedgerEntry."Document Type"::Payment);
        Assert.RecordIsNotEmpty(CustLedgerEntry);
    end;

    [Test]
    procedure ListingCustomerPaymentJournalsRunsOnOpenPage()
    var
        ResponseText: Text;
    begin
        // GET on the collection runs the page's OnOpenPage trigger (filter on the default customer payments template)
        LibraryGraphMgt.GetFromWebService(ResponseText, ApiUrl(Page::"APIV1 - Cust. Paym. Journals"));

        Assert.AreNotEqual('', ResponseText, 'The API should return a response body');
    end;

    [Test]
    procedure CreatingCustomerPaymentJournalRunsOnNewRecord()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        GraphMgtJournal: Codeunit "Graph Mgt - Journal";
        ResponseText: Text;
        BatchName: Code[10];
    begin
        BatchName := LibraryUtility.GenerateRandomCode(GenJournalBatch.FieldNo(Name), Database::"Gen. Journal Batch");

        // POST runs the OnNewRecord trigger, which assigns the default customer payments template
        LibraryGraphMgt.PostToWebService(
          ApiUrl(Page::"APIV1 - Cust. Paym. Journals"),
          StrSubstNo('{"code":"%1","displayName":"Opmetrix test"}', BatchName), ResponseText);

        GenJournalBatch.Get(GraphMgtJournal.GetDefaultCustomerPaymentsTemplateName(), BatchName);
    end;

    local procedure CreatePaymentLine(var GenJournalBatch: Record "Gen. Journal Batch"; var GenJournalLine: Record "Gen. Journal Line"; CustomerNo: Code[20])
    var
        GenJournalTemplate: Record "Gen. Journal Template";
    begin
        LibraryERM.CreateGenJournalTemplate(GenJournalTemplate);
        GenJournalTemplate.Validate(Type, GenJournalTemplate.Type::"Cash Receipts");
        GenJournalTemplate.Modify(true);
        LibraryERM.CreateGenJournalBatch(GenJournalBatch, GenJournalTemplate.Name);
        LibraryERM.CreateGeneralJnlLineWithBalAcc(
          GenJournalLine, GenJournalTemplate.Name, GenJournalBatch.Name,
          GenJournalLine."Document Type"::Payment, GenJournalLine."Account Type"::Customer, CustomerNo,
          GenJournalLine."Bal. Account Type"::"G/L Account", LibraryERM.CreateGLAccountNo(),
          -LibraryRandom.RandDecInRange(100, 1000, 2));
    end;

    local procedure ApiUrl(PageId: Integer): Text
    begin
        exit(GetUrl(ClientType::Api, CompanyName(), ObjectType::Page, PageId));
    end;

    [ConfirmHandler]
    procedure ConfirmHandlerYes(Question: Text[1024]; var Reply: Boolean)
    begin
        Reply := true;
    end;

    [MessageHandler]
    procedure MessageHandler(Message: Text[1024])
    begin
    end;
}
