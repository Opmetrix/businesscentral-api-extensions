#if TESTAPP
/// <summary>
/// Tests for posting a prepayment credit memo with the Post Prepayments codeunit (50130): each test first posts the prepayment
/// invoice through the Prepayments API page and then reverses it.
/// NOTE: posting commits, so these tests cannot be rolled back. Run them on a disposable sandbox.
/// </summary>
codeunit 50205 "OPM Prepmt. Credit Memo Tests"
{
    Subtype = Test;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "OPM Test Helper";
        PostPrepayments: Codeunit "Post Prepayments";

    [Test]
    procedure CreditMemoReversesPrepaymentInvoice()
    var
        SalesHeader: Record "Sales Header";
    begin
        Helper.CreateOrder(SalesHeader, 2, false);

        PostInvoiceThenCreditMemo(SalesHeader);

        VerifyCreditMemoPosted(SalesHeader);
    end;

    [Test]
    procedure CreditMemoForPricesIncludingVATOrder()
    var
        SalesHeader: Record "Sales Header";
    begin
        Helper.CreateOrder(SalesHeader, 2, true);

        PostInvoiceThenCreditMemo(SalesHeader);

        VerifyCreditMemoPosted(SalesHeader);
    end;

    [Test]
    procedure CreditMemoWithoutCompressionCreatesLinePerOrderLine()
    var
        SalesHeader: Record "Sales Header";
        SalesCrMemoLine: Record "Sales Cr.Memo Line";
    begin
        Helper.CreateOrder(SalesHeader, 3, false);
        SalesHeader.Validate("Compress Prepayment", false);
        SalesHeader.Modify(true);

        PostInvoiceThenCreditMemo(SalesHeader);

        VerifyCreditMemoPosted(SalesHeader);
        SalesCrMemoLine.SetRange("Document No.", SalesHeader."Last Prepmt. Cr. Memo No.");
        Assert.RecordCount(SalesCrMemoLine, 3);
    end;

    [Test]
    procedure CommentsAreCopiedToPostedPrepaymentCreditMemo()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        SalesCommentLine: Record "Sales Comment Line";
    begin
        Helper.SetCopyCommentsOrderToInvoice(true);
        Helper.CreateOrder(SalesHeader, 1, false);
        Helper.CreateSalesComment(SalesHeader."No.", 0);
        SalesLine.SetRange("Document Type", SalesHeader."Document Type");
        SalesLine.SetRange("Document No.", SalesHeader."No.");
        SalesLine.FindFirst();
        Helper.CreateSalesComment(SalesHeader."No.", SalesLine."Line No.");

        PostInvoiceThenCreditMemo(SalesHeader);

        SalesCommentLine.SetRange("Document Type", SalesCommentLine."Document Type"::"Posted Credit Memo");
        SalesCommentLine.SetRange("No.", SalesHeader."Last Prepmt. Cr. Memo No.");
        Assert.RecordIsNotEmpty(SalesCommentLine);
        Helper.SetCopyCommentsOrderToInvoice(false);
    end;

    [Test]
    procedure ExtendedTextOnPrepaymentAccountIsAddedToCreditMemo()
    var
        SalesHeader: Record "Sales Header";
        GLAccount: Record "G/L Account";
        ExtendedTextHeader: Record "Extended Text Header";
        ExtendedTextLine: Record "Extended Text Line";
        SalesCrMemoLine: Record "Sales Cr.Memo Line";
    begin
        Helper.CreateOrder(SalesHeader, 1, false);
        GLAccount.Get(Helper.PrepaymentGLAccountNoValue());
        GLAccount."Automatic Ext. Texts" := true;
        GLAccount.Modify();

        ExtendedTextHeader.Init();
        ExtendedTextHeader."Table Name" := ExtendedTextHeader."Table Name"::"G/L Account";
        ExtendedTextHeader."No." := GLAccount."No.";
        ExtendedTextHeader."Text No." := 1;
        ExtendedTextHeader."All Language Codes" := true;
        ExtendedTextHeader."Prepmt. Sales Credit Memo" := true;
        ExtendedTextHeader.Insert();
        ExtendedTextLine.Init();
        ExtendedTextLine."Table Name" := ExtendedTextHeader."Table Name";
        ExtendedTextLine."No." := ExtendedTextHeader."No.";
        ExtendedTextLine."Text No." := ExtendedTextHeader."Text No.";
        ExtendedTextLine."Line No." := 10000;
        ExtendedTextLine.Text := 'Opmetrix prepayment credit memo text';
        ExtendedTextLine.Insert();

        PostInvoiceThenCreditMemo(SalesHeader);

        SalesCrMemoLine.SetRange("Document No.", SalesHeader."Last Prepmt. Cr. Memo No.");
        SalesCrMemoLine.SetRange(Description, ExtendedTextLine.Text);
        Assert.RecordIsNotEmpty(SalesCrMemoLine);
    end;

    [Test]
    procedure PaymentTermsWithoutDiscountOnCreditMemosClearTheDiscount()
    var
        SalesHeader: Record "Sales Header";
    begin
        Helper.CreateOrder(SalesHeader, 1, false);
        SalesHeader.Validate("Prepmt. Payment Terms Code", Helper.CreatePaymentTerms(false));
        SalesHeader.Modify(true);

        PostInvoiceThenCreditMemo(SalesHeader);

        VerifyCreditMemoPosted(SalesHeader);
    end;

    [Test]
    procedure PaymentTermsWithDiscountOnCreditMemosKeepTheDiscount()
    var
        SalesHeader: Record "Sales Header";
    begin
        Helper.CreateOrder(SalesHeader, 1, false);
        SalesHeader.Validate("Prepmt. Payment Terms Code", Helper.CreatePaymentTerms(true));
        SalesHeader.Modify(true);

        PostInvoiceThenCreditMemo(SalesHeader);

        VerifyCreditMemoPosted(SalesHeader);
    end;

    [Test]
    procedure CreditMemoWithBalancingAccountPostsRefund()
    var
        SalesHeader: Record "Sales Header";
        CustLedgerEntry: Record "Cust. Ledger Entry";
    begin
        Helper.CreateOrder(SalesHeader, 1, false);
        SalesHeader.Validate("Bal. Account Type", SalesHeader."Bal. Account Type"::"Bank Account");
        SalesHeader.Validate("Bal. Account No.", Helper.CreateBankAccount());
        SalesHeader.Modify(true);

        PostInvoiceThenCreditMemo(SalesHeader);

        VerifyCreditMemoPosted(SalesHeader);
        CustLedgerEntry.SetRange("Customer No.", SalesHeader."Bill-to Customer No.");
        CustLedgerEntry.SetRange("Document Type", CustLedgerEntry."Document Type"::Refund);
        Assert.RecordIsNotEmpty(CustLedgerEntry);
    end;

    [Test]
    procedure CreditMemoForForeignCurrencyOrder()
    var
        SalesHeader: Record "Sales Header";
    begin
        Helper.CreateOrderWithCurrency(SalesHeader, 3, false, Helper.CreateCurrencyWithExchangeRate());

        PostInvoiceThenCreditMemo(SalesHeader);

        VerifyCreditMemoPosted(SalesHeader);
    end;

    [Test]
    procedure CreditMemoForForeignCurrencyOrderWithPricesIncludingVAT()
    var
        SalesHeader: Record "Sales Header";
    begin
        Helper.CreateOrderWithCurrency(SalesHeader, 3, true, Helper.CreateCurrencyWithExchangeRate());

        PostInvoiceThenCreditMemo(SalesHeader);

        VerifyCreditMemoPosted(SalesHeader);
    end;

    [Test]
    procedure CreditMemoMarkedAsCorrection()
    var
        SalesHeader: Record "Sales Header";
        GeneralLedgerSetup: Record "General Ledger Setup";
        OriginalValue: Boolean;
    begin
        GeneralLedgerSetup.Get();
        OriginalValue := GeneralLedgerSetup."Mark Cr. Memos as Corrections";
        GeneralLedgerSetup."Mark Cr. Memos as Corrections" := true;
        GeneralLedgerSetup.Modify();
        Helper.CreateOrder(SalesHeader, 1, false);

        PostInvoiceThenCreditMemo(SalesHeader);

        VerifyCreditMemoPosted(SalesHeader);
        GeneralLedgerSetup."Mark Cr. Memos as Corrections" := OriginalValue;
        GeneralLedgerSetup.Modify();
    end;

    [Test]
    procedure CreditMemoWithoutInvoicedPrepaymentIsRejected()
    var
        SalesHeader: Record "Sales Header";
    begin
        Helper.CreateOrder(SalesHeader, 1, false);
        Helper.SetPrepaymentPercent(SalesHeader, 100);

        asserterror PostPrepayments.PostPrepaymentCreditMemo(SalesHeader);

        Assert.ExpectedError('There is nothing to post.');
    end;

    local procedure PostInvoiceThenCreditMemo(var SalesHeader: Record "Sales Header")
    begin
        Helper.CreatePrepaymentViaApi(SalesHeader);
        Helper.ReopenOrder(SalesHeader);
        // A new instance each time: the codeunit keeps its posting codeunit (and the next entry numbers) between calls, and the
        // prepayment invoice was just posted by another instance
        Clear(PostPrepayments);
        PostPrepayments.PostPrepaymentCreditMemo(SalesHeader);
        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
    end;

    local procedure VerifyCreditMemoPosted(SalesHeader: Record "Sales Header")
    var
        SalesCrMemoHeader: Record "Sales Cr.Memo Header";
        SalesLine: Record "Sales Line";
    begin
        Assert.AreNotEqual('', SalesHeader."Last Prepmt. Cr. Memo No.", 'Last Prepmt. Cr. Memo No. should be set');
        SalesCrMemoHeader.Get(SalesHeader."Last Prepmt. Cr. Memo No.");
        Assert.IsTrue(SalesCrMemoHeader."Prepayment Credit Memo", 'Posted document should be a prepayment credit memo');
        Assert.AreEqual(SalesHeader."No.", SalesCrMemoHeader."Prepayment Order No.", 'Prepayment Order No.');

        SalesLine.SetRange("Document Type", SalesHeader."Document Type");
        SalesLine.SetRange("Document No.", SalesHeader."No.");
        SalesLine.CalcSums("Prepmt. Amt. Inv.");
        Assert.AreEqual(0, SalesLine."Prepmt. Amt. Inv.", 'The invoiced prepayment should be reversed');
    end;
}
#endif
