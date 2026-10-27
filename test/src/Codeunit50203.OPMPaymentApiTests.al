#if TESTAPP
/// <summary>
/// Tests for the customer payment journal API page (page 50128) and the customer payments API page (page 50129).
/// The page actions are called directly on page variables. The page triggers (OnOpenPage, OnNewRecord) only run when the page is
/// served over OData, so they are exercised by Measure-Coverage.ps1 while coverage tracking is on.
/// NOTE: posting commits, so these tests cannot be rolled back. Run them on a disposable sandbox.
/// </summary>
codeunit 50203 "OPM Payment API Tests"
{
    Subtype = Test;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "OPM Test Helper";

    [Test]
    [HandlerFunctions('MessageHandler')]
    procedure PostCustomerPaymentJournalPostsAllLinesInBatch()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        CustLedgerEntry: Record "Cust. Ledger Entry";
        PaymentJournals: Page "APIV1 - Cust. Paym. Journals";
        ActionContext: WebServiceActionContext;
        CustomerNo: Code[20];
    begin
        Helper.CreatePaymentLine(GenJournalBatch, GenJournalLine, CustomerNo);

        PaymentJournals.SetRecord(GenJournalBatch);
        PaymentJournals.post(ActionContext);

        CustLedgerEntry.SetRange("Customer No.", CustomerNo);
        CustLedgerEntry.SetRange("Document Type", CustLedgerEntry."Document Type"::Payment);
        Assert.RecordIsNotEmpty(CustLedgerEntry);
    end;

    [Test]
    procedure PostCustomerPaymentJournalWithNoLinesIsRejected()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        PaymentJournals: Page "APIV1 - Cust. Paym. Journals";
        ActionContext: WebServiceActionContext;
        CustomerNo: Code[20];
    begin
        Helper.CreatePaymentLine(GenJournalBatch, GenJournalLine, CustomerNo);
        GenJournalLine.Delete();

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
    [HandlerFunctions('MessageHandler')]
    procedure PostCustomerPaymentPostsJournalLine()
    var
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJournalLine: Record "Gen. Journal Line";
        CustLedgerEntry: Record "Cust. Ledger Entry";
        CustomerPayments: Page CustomerPayments;
        ActionContext: WebServiceActionContext;
        CustomerNo: Code[20];
    begin
        Helper.CreatePaymentLine(GenJournalBatch, GenJournalLine, CustomerNo);

        CustomerPayments.SetRecord(GenJournalLine);
        CustomerPayments.post(ActionContext);

        CustLedgerEntry.SetRange("Customer No.", CustomerNo);
        CustLedgerEntry.SetRange("Document Type", CustLedgerEntry."Document Type"::Payment);
        Assert.RecordIsNotEmpty(CustLedgerEntry);
    end;

    [MessageHandler]
    procedure MessageHandler(Message: Text[1024])
    begin
    end;
}
#endif
