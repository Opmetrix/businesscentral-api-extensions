#if TESTAPP
#if TESTAPP
/// <summary>
/// Direct tests of the public procedures of the Post Prepayments codeunit (50130).
/// NOTE: posting commits, so these tests cannot be rolled back. Run them on a disposable BC container.
/// </summary>
codeunit 50202 "OPM Post Prepayments Tests"
{
    Subtype = Test;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "OPM Test Helper";
        PostPrepayments: Codeunit "Post Prepayments";
        DocumentTypeStatistic: Option Invoice,"Credit Memo",Statistic;

    [Test]
    procedure PostPrepaymentInvoiceCreatesPostedInvoice()
    var
        SalesHeader: Record "Sales Header";
        SalesInvoiceHeader: Record "Sales Invoice Header";
    begin
        CreateOrderReadyForPrepayment(SalesHeader, 2, 100);

        PostPrepayments.PostPrepaymentInvoice(SalesHeader);

        SalesInvoiceHeader.SetRange("Prepayment Order No.", SalesHeader."No.");
        Assert.RecordCount(SalesInvoiceHeader, 1);
    end;

    [Test]
    procedure SecondPrepaymentInvoiceDeductsEarlierOne()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        SalesInvoiceHeader: Record "Sales Invoice Header";
    begin
        CreateOrderReadyForPrepayment(SalesHeader, 1, 50);
        PostPrepayments.PostPrepaymentInvoice(SalesHeader);

        // Raise the prepayment % so that only part of the new prepayment has been invoiced
        Helper.ReopenOrder(SalesHeader);
        Helper.SetPrepaymentPercent(SalesHeader, 100);
        SalesHeader.Validate("Prepayment Due Date", SalesHeader."Due Date");
        SalesHeader.Modify(true);
        SalesLine.SetRange("Document Type", SalesHeader."Document Type");
        SalesLine.SetRange("Document No.", SalesHeader."No.");
        SalesLine.FindFirst();
        Assert.AreNotEqual(SalesLine."Prepmt. Line Amount", SalesLine."Prepmt. Amt. Inv.", 'A new prepayment amount is expected');

        PostPrepayments.PostPrepaymentInvoice(SalesHeader);

        SalesInvoiceHeader.SetRange("Prepayment Order No.", SalesHeader."No.");
        Assert.RecordCount(SalesInvoiceHeader, 2);
    end;

    [Test]
    procedure PostPrepaymentInvoiceWithoutDueDateShowsErrors()
    var
        SalesHeader: Record "Sales Header";
    begin
        CreateOrderReadyForPrepayment(SalesHeader, 1, 100);
        SalesHeader."Prepayment Due Date" := 0D;
        SalesHeader.Modify();

        asserterror PostPrepayments.PostPrepaymentInvoice(SalesHeader);

        Assert.ExpectedErrorCode('Dialog');
    end;

    [Test]
    procedure CheckPrepmtDocAcceptsValidOrder()
    var
        SalesHeader: Record "Sales Header";
    begin
        CreateOrderReadyForPrepayment(SalesHeader, 1, 100);

        PostPrepayments.CheckPrepmtDoc(SalesHeader, 0);
    end;

    [Test]
    procedure CheckPrepmtDocChecksBillToCustomerWhenDifferent()
    var
        SalesHeader: Record "Sales Header";
        BillToCustomer: Record Customer;
    begin
        CreateOrderReadyForPrepayment(SalesHeader, 1, 100);
        // Same posting groups as the sell-to customer so the order stays valid
        Helper.CreateCustomer(BillToCustomer);
        SalesHeader."Bill-to Customer No." := BillToCustomer."No.";

        PostPrepayments.CheckPrepmtDoc(SalesHeader, 0);

        BillToCustomer.Blocked := BillToCustomer.Blocked::All;
        BillToCustomer.Modify();
        asserterror PostPrepayments.CheckPrepmtDoc(SalesHeader, 0);
        Assert.AreNotEqual('', GetLastErrorText(), 'A blocked bill-to customer should be rejected');
    end;

    [Test]
    procedure CheckPrepmtDocRejectsBlockedCustomer()
    var
        SalesHeader: Record "Sales Header";
        Customer: Record Customer;
    begin
        CreateOrderReadyForPrepayment(SalesHeader, 1, 100);
        Customer.Get(SalesHeader."Sell-to Customer No.");
        Customer.Blocked := Customer.Blocked::All;
        Customer.Modify();

        asserterror PostPrepayments.CheckPrepmtDoc(SalesHeader, 0);

        Assert.AreNotEqual('', GetLastErrorText(), 'A blocked customer should be rejected');
    end;

    [Test]
    procedure CheckPrepmtDocRejectsNonOrder()
    var
        SalesHeader: Record "Sales Header";
    begin
        Helper.CreateInvoiceHeader(SalesHeader);

        asserterror PostPrepayments.CheckPrepmtDoc(SalesHeader, 0);

        Assert.ExpectedErrorCode('TestField');
    end;

    [Test]
    procedure CheckPrepmtDocRejectsMissingDates()
    var
        SalesHeader: Record "Sales Header";
    begin
        CreateOrderReadyForPrepayment(SalesHeader, 1, 100);
        SalesHeader."Posting Date" := 0D;
        asserterror PostPrepayments.CheckPrepmtDoc(SalesHeader, 0);
        Assert.ExpectedErrorCode('TestField');

        SalesHeader."Posting Date" := WorkDate();
        SalesHeader."Document Date" := 0D;
        asserterror PostPrepayments.CheckPrepmtDoc(SalesHeader, 0);
        Assert.ExpectedErrorCode('TestField');

        SalesHeader."Sell-to Customer No." := '';
        asserterror PostPrepayments.CheckPrepmtDoc(SalesHeader, 0);
        Assert.ExpectedErrorCode('TestField');
    end;

    [Test]
    procedure CheckPrepmtDocRejectsPostingDateOutsideAllowedRange()
    var
        SalesHeader: Record "Sales Header";
        GeneralLedgerSetup: Record "General Ledger Setup";
        OriginalFrom: Date;
        OriginalTo: Date;
    begin
        CreateOrderReadyForPrepayment(SalesHeader, 1, 100);
        GeneralLedgerSetup.Get();
        OriginalFrom := GeneralLedgerSetup."Allow Posting From";
        OriginalTo := GeneralLedgerSetup."Allow Posting To";
        GeneralLedgerSetup."Allow Posting From" := CalcDate('<+10D>', WorkDate());
        GeneralLedgerSetup."Allow Posting To" := CalcDate('<+20D>', WorkDate());
        GeneralLedgerSetup.Modify();

        asserterror PostPrepayments.CheckPrepmtDoc(SalesHeader, 0);

        GeneralLedgerSetup."Allow Posting From" := OriginalFrom;
        GeneralLedgerSetup."Allow Posting To" := OriginalTo;
        GeneralLedgerSetup.Modify();
        Assert.ExpectedError('is not within your range of allowed posting dates');
    end;

    [Test]
    procedure CheckPrepmtDocRejectsOrderWithNothingToPost()
    var
        SalesHeader: Record "Sales Header";
    begin
        Helper.CreateOrder(SalesHeader, 1, false); // prepayment % = 0

        asserterror PostPrepayments.CheckPrepmtDoc(SalesHeader, 0);

        Assert.ExpectedError('There is nothing to post.');
    end;

    [Test]
    procedure CheckPrepmtDocRefreshesMissingPrepaymentSetupFields()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
    begin
        CreateOrderReadyForPrepayment(SalesHeader, 1, 100);
        SalesLine.SetRange("Document Type", SalesHeader."Document Type");
        SalesLine.SetRange("Document No.", SalesHeader."No.");
        SalesLine.FindFirst();
        SalesLine."Prepayment VAT Identifier" := '';
        SalesLine.Modify();

        PostPrepayments.CheckPrepmtDoc(SalesHeader, 0);

        SalesLine.Get(SalesLine."Document Type", SalesLine."Document No.", SalesLine."Line No.");
        Assert.AreNotEqual('', SalesLine."Prepayment VAT Identifier", 'Prepayment VAT Identifier should be refreshed');
    end;

    [Test]
    procedure GetInvRoundingAccNoReturnsCustomerPostingGroupAccount()
    var
        SalesHeader: Record "Sales Header";
        CustomerPostingGroup: Record "Customer Posting Group";
    begin
        Helper.CreateOrder(SalesHeader, 1, false);
        CustomerPostingGroup.Get(SalesHeader."Customer Posting Group");

        Assert.AreEqual(
          CustomerPostingGroup."Invoice Rounding Account",
          PostPrepayments.GetInvRoundingAccNo(SalesHeader."Customer Posting Group"), 'Invoice rounding account');
    end;

    [Test]
    procedure GetCorrBalAccNoUsesRoundingAccountInLCY()
    var
        SalesHeader: Record "Sales Header";
    begin
        Helper.CreateOrder(SalesHeader, 1, false);

        Assert.AreEqual(
          PostPrepayments.GetInvRoundingAccNo(SalesHeader."Customer Posting Group"),
          PostPrepayments.GetCorrBalAccNo(SalesHeader, true), 'LCY correction account');
    end;

    [Test]
    procedure GetCorrBalAccNoUsesRealizedGainOrLossInForeignCurrency()
    var
        SalesHeader: Record "Sales Header";
        Currency: Record Currency;
    begin
        Helper.CreateOrderWithCurrency(
          SalesHeader, 1, false, Helper.CreateCurrencyWithExchangeRate());
        Currency.Get(SalesHeader."Currency Code");

        Assert.AreEqual(Currency.GetRealizedGainsAccount(), PostPrepayments.GetCorrBalAccNo(SalesHeader, true), 'Gain account');
        Assert.AreEqual(Currency.GetRealizedLossesAccount(), PostPrepayments.GetCorrBalAccNo(SalesHeader, false), 'Loss account');
    end;

    [Test]
    procedure BuildInvLineBufferCreatesOneLinePerPrepaymentLine()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        TempVATAmountLine: Record "VAT Amount Line" temporary;
        TempPrepaymentInvLineBuffer: Record "Prepayment Inv. Line Buffer" temporary;
    begin
        CreateOrderReadyForPrepayment(SalesHeader, 3, 100);
        SalesHeader."Compress Prepayment" := false;
        PostPrepayments.CalcVATAmountLines(SalesHeader, SalesLine, TempVATAmountLine, DocumentTypeStatistic::Statistic);
        PostPrepayments.UpdateVATOnLines(SalesHeader, SalesLine, TempVATAmountLine, DocumentTypeStatistic::Statistic);

        PostPrepayments.BuildInvLineBuffer(SalesHeader, SalesLine, DocumentTypeStatistic::Statistic, TempPrepaymentInvLineBuffer);

        Assert.RecordCount(TempPrepaymentInvLineBuffer, 3);
        TempPrepaymentInvLineBuffer.CalcSums(Amount);
        Assert.AreEqual(Helper.OrderTotalLineAmount(SalesHeader), TempPrepaymentInvLineBuffer.Amount, 'Buffer amount');
    end;

    [Test]
    procedure BuildInvLineBufferAddsInvoiceRoundingLine()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        TempVATAmountLine: Record "VAT Amount Line" temporary;
        TempPrepaymentInvLineBuffer: Record "Prepayment Inv. Line Buffer" temporary;
    begin
        Helper.SetInvoiceRounding(true);
        Helper.SetInvRoundingPrecisionLCY(1);
        Helper.CreateOrder(SalesHeader, 1, false);
        SalesLine.SetRange("Document Type", SalesHeader."Document Type");
        SalesLine.SetRange("Document No.", SalesHeader."No.");
        SalesLine.FindFirst();
        SalesLine.Validate(Quantity, 1);
        SalesLine.Validate("Unit Price", 100.37);
        SalesLine.Modify(true);
        Helper.SetPrepaymentPercent(SalesHeader, 100);
        PostPrepayments.CalcVATAmountLines(SalesHeader, SalesLine, TempVATAmountLine, DocumentTypeStatistic::Statistic);
        PostPrepayments.UpdateVATOnLines(SalesHeader, SalesLine, TempVATAmountLine, DocumentTypeStatistic::Statistic);

        PostPrepayments.BuildInvLineBuffer(SalesHeader, SalesLine, DocumentTypeStatistic::Statistic, TempPrepaymentInvLineBuffer);

        TempPrepaymentInvLineBuffer.SetRange("Invoice Rounding", true);
        Assert.RecordIsNotEmpty(TempPrepaymentInvLineBuffer);
        Helper.SetInvoiceRounding(false);
    end;

    [Test]
    procedure BuildInvLineBufferRejectsNegativeQuantity()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        TempPrepaymentInvLineBuffer: Record "Prepayment Inv. Line Buffer" temporary;
    begin
        CreateOrderReadyForPrepayment(SalesHeader, 1, 100);
        SalesLine.SetRange("Document Type", SalesHeader."Document Type");
        SalesLine.SetRange("Document No.", SalesHeader."No.");
        SalesLine.FindFirst();
        SalesLine.Quantity := -1;
        SalesLine.Modify();

        asserterror PostPrepayments.BuildInvLineBuffer(SalesHeader, SalesLine, DocumentTypeStatistic::Statistic, TempPrepaymentInvLineBuffer);

        Assert.ExpectedError('must be positive');
    end;

    [Test]
    procedure BuildInvLineBufferRejectsNegativeUnitPrice()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        TempPrepaymentInvLineBuffer: Record "Prepayment Inv. Line Buffer" temporary;
    begin
        CreateOrderReadyForPrepayment(SalesHeader, 1, 100);
        SalesLine.SetRange("Document Type", SalesHeader."Document Type");
        SalesLine.SetRange("Document No.", SalesHeader."No.");
        SalesLine.FindFirst();
        SalesLine."Unit Price" := -1;
        SalesLine.Modify();

        asserterror PostPrepayments.BuildInvLineBuffer(SalesHeader, SalesLine, DocumentTypeStatistic::Statistic, TempPrepaymentInvLineBuffer);

        Assert.ExpectedError('must be positive');
    end;

    [Test]
    procedure FillInvLineBufferUsesPrepaymentAccountAndLineAmounts()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        PrepaymentInvLineBuffer: Record "Prepayment Inv. Line Buffer";
    begin
        CreateOrderReadyForPrepayment(SalesHeader, 1, 100);
        SalesLine.SetRange("Document Type", SalesHeader."Document Type");
        SalesLine.SetRange("Document No.", SalesHeader."No.");
        SalesLine.FindFirst();

        // Not compressed: the buffer line keeps the sales line number and description
        SalesHeader."Compress Prepayment" := false;
        PostPrepayments.FillInvLineBuffer(SalesHeader, SalesLine, PrepaymentInvLineBuffer);
        Assert.AreEqual(SalesLine."Line No.", PrepaymentInvLineBuffer."Line No.", 'Line No.');
        Assert.AreEqual(SalesLine."Prepayment Amount", PrepaymentInvLineBuffer.Amount, 'Amount');
        Assert.AreNotEqual('', PrepaymentInvLineBuffer."G/L Account No.", 'Prepayment G/L account');

        // Compressed: line identity is dropped
        SalesHeader."Compress Prepayment" := true;
        Clear(PrepaymentInvLineBuffer);
        PostPrepayments.FillInvLineBuffer(SalesHeader, SalesLine, PrepaymentInvLineBuffer);
        Assert.AreEqual(0, PrepaymentInvLineBuffer."Line No.", 'Line No. when compressed');
    end;

    [Test]
    procedure CalcAndUpdateVATLinesFillPrepaymentAmounts()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        TempVATAmountLine: Record "VAT Amount Line" temporary;
    begin
        CreateOrderReadyForPrepayment(SalesHeader, 2, 100);

        PostPrepayments.CalcVATAmountLines(SalesHeader, SalesLine, TempVATAmountLine, DocumentTypeStatistic::Statistic);
        PostPrepayments.UpdateVATOnLines(SalesHeader, SalesLine, TempVATAmountLine, DocumentTypeStatistic::Statistic);

        Assert.RecordCount(TempVATAmountLine, 1);
        TempVATAmountLine.CalcSums("Line Amount");
        Assert.AreEqual(Helper.OrderTotalLineAmount(SalesHeader), TempVATAmountLine."Line Amount", 'VAT line amount');
        SalesLine.SetRange("Document Type", SalesHeader."Document Type");
        SalesLine.SetRange("Document No.", SalesHeader."No.");
        SalesLine.FindFirst();
        Assert.AreEqual(SalesLine."Prepmt. Line Amount", SalesLine."Prepayment Amount", 'Prepayment Amount');
    end;

    [Test]
    procedure CalcAndUpdateVATLinesWithPricesIncludingVAT()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        TempVATAmountLine: Record "VAT Amount Line" temporary;
    begin
        Helper.CreateOrder(SalesHeader, 2, true);
        Helper.SetPrepaymentPercent(SalesHeader, 100);

        PostPrepayments.CalcVATAmountLines(SalesHeader, SalesLine, TempVATAmountLine, DocumentTypeStatistic::Statistic);
        PostPrepayments.UpdateVATOnLines(SalesHeader, SalesLine, TempVATAmountLine, DocumentTypeStatistic::Statistic);

        Assert.RecordCount(TempVATAmountLine, 1);
        SalesLine.SetRange("Document Type", SalesHeader."Document Type");
        SalesLine.SetRange("Document No.", SalesHeader."No.");
        SalesLine.FindFirst();
        Assert.AreEqual(SalesLine."Prepmt. Line Amount", SalesLine."Prepmt. Amt. Incl. VAT", 'Prepmt. Amt. Incl. VAT');
    end;

    [Test]
    procedure GetSalesLinesToDeductReturnsPartlyInvoicedLines()
    var
        SalesHeader: Record "Sales Header";
        TempSalesLine: Record "Sales Line" temporary;
    begin
        CreateOrderReadyForPrepayment(SalesHeader, 1, 50);
        PostPrepayments.PostPrepaymentInvoice(SalesHeader);
        Helper.ReopenOrder(SalesHeader);
        Helper.SetPrepaymentPercent(SalesHeader, 100);

        PostPrepayments.GetSalesLinesToDeduct(SalesHeader, TempSalesLine);

        Assert.RecordCount(TempSalesLine, 1);
    end;

    [Test]
    procedure GetSalesLinesToDeductIsEmptyBeforeAnyPrepaymentIsInvoiced()
    var
        SalesHeader: Record "Sales Header";
        TempSalesLine: Record "Sales Line" temporary;
    begin
        CreateOrderReadyForPrepayment(SalesHeader, 1, 100);

        PostPrepayments.GetSalesLinesToDeduct(SalesHeader, TempSalesLine);

        Assert.RecordIsEmpty(TempSalesLine);
    end;

    local procedure CreateOrderReadyForPrepayment(var SalesHeader: Record "Sales Header"; LineCount: Integer; PrepaymentPct: Decimal)
    begin
        Helper.CreateOrder(SalesHeader, LineCount, false);
        Helper.SetPrepaymentPercent(SalesHeader, PrepaymentPct);
        SalesHeader.Validate("Prepayment Due Date", SalesHeader."Due Date");
        SalesHeader.Modify(true);
    end;
}
#endif
#endif
