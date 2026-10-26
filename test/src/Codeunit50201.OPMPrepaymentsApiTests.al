#if TESTAPP
/// <summary>
/// Tests for the Prepayments API page (page 50125) and, through it, the Post Prepayments codeunit (50130).
/// NOTE: the code under test commits, so these tests cannot be rolled back. Run them on a disposable BC container.
/// </summary>
codeunit 50201 "OPM Prepayments API Tests"
{
    Subtype = Test;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "OPM Test Helper";
        LibrarySales: Codeunit "Library - Sales";
        LibraryERM: Codeunit "Library - ERM";
        LibraryRandom: Codeunit "Library - Random";

    [Test]
    procedure SingleLineOrderPostsPrepaymentInvoice()
    var
        SalesHeader: Record "Sales Header";
    begin
        Helper.CreateOrder(SalesHeader, 1, false);

        Helper.CreatePrepaymentViaApi(SalesHeader);

        VerifyPrepaymentInvoicePosted(SalesHeader);
        Assert.AreEqual(100, SalesHeader."Prepayment %", 'Prepayment % should be forced to 100');
    end;

    [Test]
    procedure MultiLineOrderSpreadsPrepaymentAcrossLines()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
    begin
        // Two normal lines plus one zero-priced line (Line Amount = 0 is skipped when allocating the prepayment)
        Helper.CreateOrder(SalesHeader, 2, false);
        LibrarySales.CreateSalesLine(SalesLine, SalesHeader, SalesLine.Type::"G/L Account", Helper.LineGLAccountNo(), 1);
        SalesLine.Validate("Unit Price", 0);
        SalesLine.Modify(true);

        Helper.CreatePrepaymentViaApi(SalesHeader);

        VerifyPrepaymentInvoicePosted(SalesHeader);
    end;

    [Test]
    procedure PricesIncludingVATOrderPostsPrepaymentInvoice()
    var
        SalesHeader: Record "Sales Header";
    begin
        Helper.CreateOrder(SalesHeader, 2, true);

        Helper.CreatePrepaymentViaApi(SalesHeader);

        VerifyPrepaymentInvoicePosted(SalesHeader);
    end;

    [Test]
    procedure HeaderAlreadyAlignedIsNotModifiedBeforePosting()
    var
        SalesHeader: Record "Sales Header";
    begin
        // Prepayment % = 100, Document Date = Posting Date and Prepayment Due Date = Due Date are already set
        Helper.CreateOrder(SalesHeader, 1, false);
        SalesHeader.Validate("Prepayment %", 100);
        SalesHeader.Validate("Prepayment Due Date", SalesHeader."Due Date");
        SalesHeader.Modify(true);

        Helper.CreatePrepaymentViaApi(SalesHeader);

        VerifyPrepaymentInvoicePosted(SalesHeader);
    end;

    [Test]
    procedure ReverseChargeVATOrderPostsPrepaymentInvoice()
    var
        SalesHeader: Record "Sales Header";
    begin
        Helper.CreateOrderWithVATCalculation(SalesHeader, 1, false, '', "Tax Calculation Type"::"Reverse Charge VAT");

        Helper.CreatePrepaymentViaApi(SalesHeader);

        VerifyPrepaymentInvoicePosted(SalesHeader);
    end;

    [Test]
    procedure FullVATOrderPostsPrepaymentInvoice()
    var
        SalesHeader: Record "Sales Header";
    begin
        Helper.CreateOrderWithVATCalculation(SalesHeader, 1, false, '', "Tax Calculation Type"::"Full VAT");

        Helper.CreatePrepaymentViaApi(SalesHeader);

        VerifyPrepaymentInvoicePosted(SalesHeader);
    end;

    [Test]
    procedure ForeignCurrencyOrderPostsPrepaymentInvoice()
    var
        SalesHeader: Record "Sales Header";
    begin
        Helper.CreateOrderWithCurrency(
          SalesHeader, 2, false, LibraryERM.CreateCurrencyWithExchangeRate(WorkDate(), 1.5, 1.5));

        Helper.CreatePrepaymentViaApi(SalesHeader);

        VerifyPrepaymentInvoicePosted(SalesHeader);
    end;

    [Test]
    procedure InvoiceRoundingAddsRoundingLine()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
    begin
        LibrarySales.SetInvoiceRounding(true);
        LibraryERM.SetInvRoundingPrecisionLCY(1);
        Helper.CreateOrder(SalesHeader, 1, false);
        SalesLine.SetRange("Document Type", SalesHeader."Document Type");
        SalesLine.SetRange("Document No.", SalesHeader."No.");
        SalesLine.FindFirst();
        SalesLine.Validate(Quantity, 1);
        SalesLine.Validate("Unit Price", 100.37);
        SalesLine.Modify(true);

        Helper.CreatePrepaymentViaApi(SalesHeader);

        VerifyPrepaymentInvoicePosted(SalesHeader);
        LibrarySales.SetInvoiceRounding(false);
    end;

    [Test]
    procedure BalancingAccountPostsPaymentEntry()
    var
        SalesHeader: Record "Sales Header";
        BankAccount: Record "Bank Account";
        CustLedgerEntry: Record "Cust. Ledger Entry";
    begin
        LibraryERM.CreateBankAccount(BankAccount);
        Helper.CreateOrder(SalesHeader, 1, false);
        SalesHeader.Validate("Bal. Account Type", SalesHeader."Bal. Account Type"::"Bank Account");
        SalesHeader.Validate("Bal. Account No.", BankAccount."No.");
        SalesHeader.Modify(true);

        Helper.CreatePrepaymentViaApi(SalesHeader);

        VerifyPrepaymentInvoicePosted(SalesHeader);
        CustLedgerEntry.SetRange("Customer No.", SalesHeader."Bill-to Customer No.");
        CustLedgerEntry.SetRange("Document Type", CustLedgerEntry."Document Type"::Payment);
        Assert.RecordIsNotEmpty(CustLedgerEntry);
    end;

    [Test]
    procedure CommentsAreCopiedToPostedPrepaymentInvoice()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        SalesCommentLine: Record "Sales Comment Line";
    begin
        LibrarySales.SetCopyCommentsOrderToInvoiceInSetup(true);
        Helper.CreateOrder(SalesHeader, 1, false);
        LibrarySales.CreateSalesCommentLine(SalesCommentLine, SalesCommentLine."Document Type"::Order, SalesHeader."No.", 0);
        SalesLine.SetRange("Document Type", SalesHeader."Document Type");
        SalesLine.SetRange("Document No.", SalesHeader."No.");
        SalesLine.FindFirst();
        LibrarySales.CreateSalesCommentLine(
          SalesCommentLine, SalesCommentLine."Document Type"::Order, SalesHeader."No.", SalesLine."Line No.");

        Helper.CreatePrepaymentViaApi(SalesHeader);

        SalesCommentLine.Reset();
        SalesCommentLine.SetRange("Document Type", SalesCommentLine."Document Type"::"Posted Invoice");
        SalesCommentLine.SetRange("No.", SalesHeader."Last Prepayment No.");
        Assert.RecordIsNotEmpty(SalesCommentLine);
    end;

    [Test]
    procedure ExtendedTextOnPrepaymentAccountIsAddedToInvoice()
    var
        SalesHeader: Record "Sales Header";
        GeneralPostingSetup: Record "General Posting Setup";
        ExtendedTextHeader: Record "Extended Text Header";
        ExtendedTextLine: Record "Extended Text Line";
        SalesInvoiceLine: Record "Sales Invoice Line";
        PrepmtAccountNo: Code[20];
    begin
        Helper.CreateOrder(SalesHeader, 1, false);
        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
        // The prepayment G/L account is taken from the posting setup of the order line
        GeneralPostingSetup.Get(SalesHeader."Gen. Bus. Posting Group", LineGenProdPostingGroup(SalesHeader));
        PrepmtAccountNo := GeneralPostingSetup.GetSalesPrepmtAccount();

        ExtendedTextHeader.Init();
        ExtendedTextHeader."Table Name" := ExtendedTextHeader."Table Name"::"G/L Account";
        ExtendedTextHeader."No." := PrepmtAccountNo;
        ExtendedTextHeader."Text No." := 1;
        ExtendedTextHeader."All Language Codes" := true;
        ExtendedTextHeader."Prepmt. Sales Invoice" := true;
        ExtendedTextHeader.Insert();
        ExtendedTextLine.Init();
        ExtendedTextLine."Table Name" := ExtendedTextHeader."Table Name";
        ExtendedTextLine."No." := ExtendedTextHeader."No.";
        ExtendedTextLine."Text No." := ExtendedTextHeader."Text No.";
        ExtendedTextLine."Line No." := 10000;
        ExtendedTextLine.Text := 'Opmetrix prepayment extended text';
        ExtendedTextLine.Insert();

        Helper.CreatePrepaymentViaApi(SalesHeader);

        SalesInvoiceLine.SetRange("Document No.", SalesHeader."Last Prepayment No.");
        SalesInvoiceLine.SetRange(Description, ExtendedTextLine.Text);
        Assert.RecordIsNotEmpty(SalesInvoiceLine);
    end;

    [Test]
    procedure ExternalDocumentNoMandatoryBlocksPostingWhenMissing()
    var
        SalesHeader: Record "Sales Header";
        SalesReceivablesSetup: Record "Sales & Receivables Setup";
    begin
        SalesReceivablesSetup.Get();
        SalesReceivablesSetup."Ext. Doc. No. Mandatory" := true;
        SalesReceivablesSetup.Modify();
        Helper.CreateOrder(SalesHeader, 1, false);

        asserterror Helper.CreatePrepaymentViaApi(SalesHeader);
        Assert.ExpectedErrorCode('TestField');

        SalesReceivablesSetup."Ext. Doc. No. Mandatory" := false;
        SalesReceivablesSetup.Modify();
    end;

    [Test]
    procedure CompressedPrepaymentCreatesSingleLinePerAccount()
    var
        SalesHeader: Record "Sales Header";
    begin
        Helper.CreateOrder(SalesHeader, 3, false);
        SalesHeader.Validate("Compress Prepayment", true);
        SalesHeader.Modify(true);

        Helper.CreatePrepaymentViaApi(SalesHeader);

        VerifyPrepaymentInvoicePosted(SalesHeader);
    end;

    [Test]
    procedure ReleasedOrderIsRejected()
    var
        SalesHeader: Record "Sales Header";
    begin
        Helper.CreateOrder(SalesHeader, 1, false);
        LibrarySales.ReleaseSalesDocument(SalesHeader);

        asserterror Helper.CreatePrepaymentViaApi(SalesHeader);

        Assert.ExpectedErrorCode('TestField');
    end;

    [Test]
    procedure NonOrderDocumentIsRejected()
    var
        SalesHeader: Record "Sales Header";
    begin
        LibrarySales.CreateSalesHeader(
          SalesHeader, SalesHeader."Document Type"::Invoice, LibrarySales.CreateCustomerNo());

        asserterror Helper.CreatePrepaymentViaApi(SalesHeader);

        Assert.ExpectedErrorCode('TestField');
    end;

    [Test]
    procedure PrepaymentAlreadyInvoicedIsRejected()
    var
        SalesHeader: Record "Sales Header";
    begin
        Helper.CreateOrder(SalesHeader, 1, false);
        Helper.CreatePrepaymentViaApi(SalesHeader);
        Helper.ReopenOrder(SalesHeader);

        asserterror Helper.CreatePrepaymentViaApi(SalesHeader);

        Assert.ExpectedError('Total prepayment amount invoiced greater than 0.');
    end;

    [Test]
    procedure MissingMandatoryHeaderFieldsAreRejected()
    var
        SalesHeader: Record "Sales Header";
    begin
        // Unsaved header: each mandatory field is checked in turn
        SalesHeader.Init();
        SalesHeader."Document Type" := SalesHeader."Document Type"::Order;

        asserterror Helper.CreatePrepaymentViaApi(SalesHeader);
        Assert.ExpectedErrorCode('TestField'); // Sell-to Customer No.

        SalesHeader."Sell-to Customer No." := 'X';
        asserterror Helper.CreatePrepaymentViaApi(SalesHeader);
        Assert.ExpectedErrorCode('TestField'); // Bill-to Customer No.

        SalesHeader."Bill-to Customer No." := 'X';
        asserterror Helper.CreatePrepaymentViaApi(SalesHeader);
        Assert.ExpectedErrorCode('TestField'); // Posting Date

        SalesHeader."Posting Date" := WorkDate();
        asserterror Helper.CreatePrepaymentViaApi(SalesHeader);
        Assert.ExpectedErrorCode('TestField'); // Due Date
    end;

    local procedure VerifyPrepaymentInvoicePosted(SalesHeader: Record "Sales Header")
    var
        SalesInvoiceHeader: Record "Sales Invoice Header";
        SalesLine: Record "Sales Line";
    begin
        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
        Assert.AreNotEqual('', SalesHeader."Last Prepayment No.", 'Last Prepayment No. should be set');
        SalesInvoiceHeader.Get(SalesHeader."Last Prepayment No.");
        Assert.IsTrue(SalesInvoiceHeader."Prepayment Invoice", 'Posted document should be a prepayment invoice');
        Assert.AreEqual(SalesHeader."No.", SalesInvoiceHeader."Prepayment Order No.", 'Prepayment Order No.');

        SalesLine.SetRange("Document Type", SalesHeader."Document Type");
        SalesLine.SetRange("Document No.", SalesHeader."No.");
        SalesLine.CalcSums("Line Amount", "Prepmt. Amt. Inv.");
        Assert.AreEqual(SalesLine."Line Amount", SalesLine."Prepmt. Amt. Inv.", 'Whole order should be invoiced as prepayment');
    end;

    local procedure LineGenProdPostingGroup(SalesHeader: Record "Sales Header"): Code[20]
    var
        SalesLine: Record "Sales Line";
    begin
        SalesLine.SetRange("Document Type", SalesHeader."Document Type");
        SalesLine.SetRange("Document No.", SalesHeader."No.");
        SalesLine.FindFirst();
        exit(SalesLine."Gen. Prod. Posting Group");
    end;
}
#endif
