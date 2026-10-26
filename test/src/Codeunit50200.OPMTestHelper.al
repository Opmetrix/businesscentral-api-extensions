#if TESTAPP
/// <summary>
/// Scenario builders for the Opmetrix extension tests. They use only platform and base application objects (no test libraries),
/// because the online sandbox has only Any, Library Assert and Test Runner installed.
/// Every scenario creates its own posting groups, G/L accounts, customer and order, so it does not depend on the demo data.
/// </summary>
codeunit 50200 "OPM Test Helper"
{
    Permissions = tabledata "No. Series" = rimd,
                  tabledata "No. Series Line" = rimd,
                  tabledata "Sales & Receivables Setup" = rimd;

    var
        Assert: Codeunit "Library Assert";
        Any: Codeunit Any;
        LineGLAccountNo: Code[20];
        PrepmtGLAccountNo: Code[20];
        VATProdPostingGroupCode: Code[20];
        VATBusPostingGroupCode: Code[20];
        GenBusPostingGroupCode: Code[20];
        GenProdPostingGroupCode: Code[20];

    /// <summary>
    /// Creates an open sales order for a new customer with G/L account lines and the posting set-up needed for prepayments.
    /// The prepayment % is left at 0 on the header.
    /// </summary>
    procedure CreateOrder(var SalesHeader: Record "Sales Header"; LineCount: Integer; PricesIncludingVAT: Boolean)
    begin
        CreateOrderWithVATCalculation(SalesHeader, LineCount, PricesIncludingVAT, '', "Tax Calculation Type"::"Normal VAT");
    end;

    procedure CreateOrderWithCurrency(var SalesHeader: Record "Sales Header"; LineCount: Integer; PricesIncludingVAT: Boolean; CurrencyCode: Code[10])
    begin
        CreateOrderWithVATCalculation(SalesHeader, LineCount, PricesIncludingVAT, CurrencyCode, "Tax Calculation Type"::"Normal VAT");
    end;

    procedure CreateOrderWithVATCalculation(var SalesHeader: Record "Sales Header"; LineCount: Integer; PricesIncludingVAT: Boolean; CurrencyCode: Code[10]; VATCalculationType: Enum "Tax Calculation Type")
    var
        SalesLine: Record "Sales Line";
        Customer: Record Customer;
        i: Integer;
    begin
        EnsurePrepaymentNoSeries();
        CreatePostingSetup(VATCalculationType);
        CreateCustomer(Customer);

        SalesHeader.Init();
        SalesHeader."Document Type" := SalesHeader."Document Type"::Order;
        SalesHeader.Insert(true);
        SalesHeader.Validate("Sell-to Customer No.", Customer."No.");
        if CurrencyCode <> '' then
            SalesHeader.Validate("Currency Code", CurrencyCode);
        SalesHeader.Validate("Prices Including VAT", PricesIncludingVAT);
        SalesHeader.Validate("Posting Date", WorkDate());
        SalesHeader.Validate("Document Date", WorkDate());
        SalesHeader.Validate("Due Date", CalcDate('<30D>', WorkDate()));
        SalesHeader.Modify(true);

        for i := 1 to LineCount do
            AddLine(SalesHeader, i * 10000, Any.IntegerInRange(1, 10), Any.DecimalInRange(100, 1000, 2));
        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
    end;

    procedure AddLine(SalesHeader: Record "Sales Header"; LineNo: Integer; Quantity: Decimal; UnitPrice: Decimal)
    var
        SalesLine: Record "Sales Line";
    begin
        SalesLine.Init();
        SalesLine."Document Type" := SalesHeader."Document Type";
        SalesLine."Document No." := SalesHeader."No.";
        SalesLine."Line No." := LineNo;
        SalesLine.Insert(true);
        SalesLine.Validate(Type, SalesLine.Type::"G/L Account");
        SalesLine.Validate("No.", LineGLAccountNo);
        SalesLine.Validate(Quantity, Quantity);
        SalesLine.Validate("Unit Price", UnitPrice);
        SalesLine.Modify(true);
    end;

    /// <summary>
    /// Sets the prepayment % on the header and on every line, so each line has a Prepmt. Line Amount (no posting).
    /// </summary>
    procedure SetPrepaymentPercent(var SalesHeader: Record "Sales Header"; PrepaymentPct: Decimal)
    var
        SalesLine: Record "Sales Line";
    begin
        SalesHeader.Validate("Prepayment %", PrepaymentPct);
        SalesHeader.Modify(true);
        SalesLine.SetRange("Document Type", SalesHeader."Document Type");
        SalesLine.SetRange("Document No.", SalesHeader."No.");
        SalesLine.FindSet(true);
        repeat
            SalesLine.Validate("Prepayment %", PrepaymentPct);
            SalesLine.Modify(true);
        until SalesLine.Next() = 0;
        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
    end;

    /// <summary>
    /// Runs the Prepayments API page action (page 50125) for the given order and checks it reports "Created".
    /// </summary>
    procedure CreatePrepaymentViaApi(var SalesHeader: Record "Sales Header")
    var
        PrepaymentsApi: Page Prepayments;
        ActionContext: WebServiceActionContext;
    begin
        PrepaymentsApi.SetRecord(SalesHeader);
        PrepaymentsApi.CreatePrepayment(ActionContext);
        Assert.IsTrue(
          Format(ActionContext.GetResultCode()) = Format(WebServiceActionResultCode::Created), 'The action should report Created');
        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
    end;

    procedure LineGLAccountNoValue(): Code[20]
    begin
        exit(LineGLAccountNo);
    end;

    procedure PrepaymentGLAccountNoValue(): Code[20]
    begin
        exit(PrepmtGLAccountNo);
    end;

    procedure GenBusPostingGroupValue(): Code[20]
    begin
        exit(GenBusPostingGroupCode);
    end;

    procedure GenProdPostingGroupValue(): Code[20]
    begin
        exit(GenProdPostingGroupCode);
    end;

    procedure VATBusPostingGroupValue(): Code[20]
    begin
        exit(VATBusPostingGroupCode);
    end;

    procedure OrderTotalLineAmount(SalesHeader: Record "Sales Header"): Decimal
    var
        SalesLine: Record "Sales Line";
    begin
        SalesLine.SetRange("Document Type", SalesHeader."Document Type");
        SalesLine.SetRange("Document No.", SalesHeader."No.");
        SalesLine.CalcSums("Line Amount");
        exit(SalesLine."Line Amount");
    end;

    procedure ReopenOrder(var SalesHeader: Record "Sales Header")
    begin
        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
        SalesHeader.Status := SalesHeader.Status::Open;
        SalesHeader.Modify();
    end;

    /// <summary>A customer with the posting groups of the current scenario and an existing customer posting group.</summary>
    procedure CreateCustomer(var Customer: Record Customer)
    var
        CustomerPostingGroup: Record "Customer Posting Group";
    begin
        CustomerPostingGroup.SetFilter("Receivables Account", '<>%1', '');
        CustomerPostingGroup.SetFilter("Invoice Rounding Account", '<>%1', '');
        CustomerPostingGroup.FindFirst();

        Customer.Init();
        Customer."No." := 'OPMC' + CopyStr(Any.AlphanumericText(5), 1, 5);
        Customer.Name := 'Opmetrix test customer';
        Customer.Insert(true);
        Customer.Validate("Customer Posting Group", CustomerPostingGroup.Code);
        Customer.Validate("Gen. Bus. Posting Group", GenBusPostingGroupCode);
        Customer.Validate("VAT Bus. Posting Group", VATBusPostingGroupCode);
        Customer.Modify(true);
    end;

    local procedure CreatePostingSetup(VATCalculationType: Enum "Tax Calculation Type")
    var
        GenBusinessPostingGroup: Record "Gen. Business Posting Group";
        GenProductPostingGroup: Record "Gen. Product Posting Group";
        VATBusinessPostingGroup: Record "VAT Business Posting Group";
        VATProductPostingGroup: Record "VAT Product Posting Group";
        VATPostingSetup: Record "VAT Posting Setup";
        GeneralPostingSetup: Record "General Posting Setup";
        GLAccount: Record "G/L Account";
        VATAccountNo: Code[20];
        Suffix: Code[10];
    begin
        Suffix := CopyStr(Any.AlphanumericText(6), 1, 6);
        GenBusPostingGroupCode := 'OB' + Suffix;
        GenProdPostingGroupCode := 'OP' + Suffix;
        VATBusPostingGroupCode := 'OB' + Suffix;
        VATProdPostingGroupCode := 'OP' + Suffix;

        GenBusinessPostingGroup.Init();
        GenBusinessPostingGroup.Code := GenBusPostingGroupCode;
        GenBusinessPostingGroup.Insert();
        GenProductPostingGroup.Init();
        GenProductPostingGroup.Code := GenProdPostingGroupCode;
        GenProductPostingGroup.Insert();
        VATBusinessPostingGroup.Init();
        VATBusinessPostingGroup.Code := VATBusPostingGroupCode;
        VATBusinessPostingGroup.Insert();
        VATProductPostingGroup.Init();
        VATProductPostingGroup.Code := VATProdPostingGroupCode;
        VATProductPostingGroup.Insert();

        // With Full VAT the sales line must use the VAT account itself as its G/L account
        if VATCalculationType = VATCalculationType::"Full VAT" then
            VATAccountNo := CreateGLAccount(GLAccount."Gen. Posting Type"::Sale, true)
        else
            VATAccountNo := CreateGLAccount(GLAccount."Gen. Posting Type"::" ", false);

        VATPostingSetup.Init();
        VATPostingSetup."VAT Bus. Posting Group" := VATBusPostingGroupCode;
        VATPostingSetup."VAT Prod. Posting Group" := VATProdPostingGroupCode;
        VATPostingSetup."VAT Calculation Type" := VATCalculationType;
        VATPostingSetup."VAT Identifier" := VATProdPostingGroupCode;
        if VATCalculationType = VATCalculationType::"Full VAT" then
            VATPostingSetup."VAT %" := 100
        else
            VATPostingSetup."VAT %" := 10;
        VATPostingSetup."Sales VAT Account" := VATAccountNo;
        VATPostingSetup."Purchase VAT Account" := VATAccountNo;
        VATPostingSetup."Reverse Chrg. VAT Acc." := VATAccountNo;
        VATPostingSetup."Tax Category" := '';
        VATPostingSetup.Insert();

        // Accounts such as the invoice rounding account use other VAT product groups, so the new VAT business group
        // needs a setup for each of them as well
        VATProductPostingGroup.SetFilter(Code, '<>%1', VATProdPostingGroupCode);
        if VATProductPostingGroup.FindSet() then
            repeat
                if not VATPostingSetup.Get(VATBusPostingGroupCode, VATProductPostingGroup.Code) then begin
                    VATPostingSetup.Init();
                    VATPostingSetup."VAT Bus. Posting Group" := VATBusPostingGroupCode;
                    VATPostingSetup."VAT Prod. Posting Group" := VATProductPostingGroup.Code;
                    VATPostingSetup."VAT Calculation Type" := VATPostingSetup."VAT Calculation Type"::"Normal VAT";
                    VATPostingSetup."VAT Identifier" := VATProductPostingGroup.Code;
                    VATPostingSetup."VAT %" := 0;
                    VATPostingSetup."Sales VAT Account" := VATAccountNo;
                    VATPostingSetup."Purchase VAT Account" := VATAccountNo;
                    VATPostingSetup.Insert();
                end;
            until VATProductPostingGroup.Next() = 0;

        if VATCalculationType = VATCalculationType::"Full VAT" then
            LineGLAccountNo := VATAccountNo
        else
            LineGLAccountNo := CreateGLAccount(GLAccount."Gen. Posting Type"::Sale, true);
        PrepmtGLAccountNo := CreateGLAccount(GLAccount."Gen. Posting Type"::Sale, true);

        GeneralPostingSetup.Init();
        GeneralPostingSetup."Gen. Bus. Posting Group" := GenBusPostingGroupCode;
        GeneralPostingSetup."Gen. Prod. Posting Group" := GenProdPostingGroupCode;
        GeneralPostingSetup."Sales Account" := LineGLAccountNo;
        GeneralPostingSetup."Sales Credit Memo Account" := LineGLAccountNo;
        GeneralPostingSetup."Sales Prepayments Account" := PrepmtGLAccountNo;
        GeneralPostingSetup.Insert();
    end;

    local procedure CreateGLAccount(GenPostingType: Enum "General Posting Type"; WithPostingGroups: Boolean): Code[20]
    var
        GLAccount: Record "G/L Account";
    begin
        GLAccount.Init();
        GLAccount."No." := 'OG' + CopyStr(Any.AlphanumericText(8), 1, 8);
        GLAccount.Name := 'Opmetrix test account';
        GLAccount."Account Type" := GLAccount."Account Type"::Posting;
        GLAccount."Direct Posting" := true;
        GLAccount."Income/Balance" := GLAccount."Income/Balance"::"Income Statement";
        GLAccount.Insert(true);
        if WithPostingGroups then begin
            GLAccount."Gen. Posting Type" := GenPostingType;
            GLAccount."Gen. Bus. Posting Group" := GenBusPostingGroupCode;
            GLAccount."Gen. Prod. Posting Group" := GenProdPostingGroupCode;
            GLAccount."VAT Bus. Posting Group" := VATBusPostingGroupCode;
            GLAccount."VAT Prod. Posting Group" := VATProdPostingGroupCode;
            GLAccount.Modify();
        end;
        exit(GLAccount."No.");
    end;

    local procedure EnsurePrepaymentNoSeries()
    var
        SalesReceivablesSetup: Record "Sales & Receivables Setup";
    begin
        SalesReceivablesSetup.Get();
        // Every scenario starts from the same defaults, whatever an earlier test changed
        SalesReceivablesSetup."Ext. Doc. No. Mandatory" := false;
        if SalesReceivablesSetup."Posted Prepmt. Inv. Nos." = '' then
            SalesReceivablesSetup."Posted Prepmt. Inv. Nos." := CreateNoSeries('OPMPINV', 'OPMPI000001');
        if SalesReceivablesSetup."Posted Prepmt. Cr. Memo Nos." = '' then
            SalesReceivablesSetup."Posted Prepmt. Cr. Memo Nos." := CreateNoSeries('OPMPCR', 'OPMPC000001');
        SalesReceivablesSetup.Modify();
        Commit();
    end;

    local procedure CreateNoSeries(SeriesCode: Code[20]; StartingNo: Code[20]): Code[20]
    var
        NoSeries: Record "No. Series";
        NoSeriesLine: Record "No. Series Line";
    begin
        if NoSeries.Get(SeriesCode) then
            exit(SeriesCode);
        NoSeries.Init();
        NoSeries.Code := SeriesCode;
        NoSeries.Description := 'Opmetrix tests';
        NoSeries."Default Nos." := true;
        NoSeries."Manual Nos." := true;
        NoSeries.Insert();
        NoSeriesLine.Init();
        NoSeriesLine."Series Code" := SeriesCode;
        NoSeriesLine."Line No." := 10000;
        NoSeriesLine."Starting No." := StartingNo;
        NoSeriesLine."Increment-by No." := 1;
        NoSeriesLine.Insert(true);
        exit(SeriesCode);
    end;

    /// <summary>A sales invoice header for the current scenario (used to test document type checks).</summary>
    procedure CreateInvoiceHeader(var SalesHeader: Record "Sales Header")
    var
        Customer: Record Customer;
    begin
        CreatePostingSetup("Tax Calculation Type"::"Normal VAT");
        CreateCustomer(Customer);
        SalesHeader.Init();
        SalesHeader."Document Type" := SalesHeader."Document Type"::Invoice;
        SalesHeader.Insert(true);
        SalesHeader.Validate("Sell-to Customer No.", Customer."No.");
        SalesHeader.Modify(true);
    end;

    procedure ReleaseOrder(var SalesHeader: Record "Sales Header")
    var
        ReleaseSalesDocument: Codeunit "Release Sales Document";
    begin
        ReleaseSalesDocument.PerformManualRelease(SalesHeader);
        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
    end;

    /// <summary>A foreign currency with exchange rate and all the G/L accounts a posting needs.</summary>
    procedure CreateCurrencyWithExchangeRate(): Code[10]
    var
        Currency: Record Currency;
        CurrencyExchangeRate: Record "Currency Exchange Rate";
        GLAccount: Record "G/L Account";
        AccountNo: Code[20];
    begin
        AccountNo := CreateGLAccount(GLAccount."Gen. Posting Type"::" ", false);
        Currency.Init();
        Currency.Code := 'O' + CopyStr(Any.AlphanumericText(2), 1, 2);
        Currency.Insert(true);
        Currency."Unrealized Gains Acc." := AccountNo;
        Currency."Realized Gains Acc." := AccountNo;
        Currency."Unrealized Losses Acc." := AccountNo;
        Currency."Realized Losses Acc." := AccountNo;
        Currency."Residual Gains Account" := AccountNo;
        Currency."Residual Losses Account" := AccountNo;
        Currency."Amount Rounding Precision" := 0.01;
        Currency."Invoice Rounding Precision" := 0.01;
        Currency.Modify();

        CurrencyExchangeRate.Init();
        CurrencyExchangeRate."Currency Code" := Currency.Code;
        CurrencyExchangeRate."Starting Date" := 0D;
        CurrencyExchangeRate."Exchange Rate Amount" := 1;
        CurrencyExchangeRate."Adjustment Exch. Rate Amount" := 1;
        CurrencyExchangeRate."Relational Exch. Rate Amount" := 1.5;
        CurrencyExchangeRate."Relational Adjmt Exch Rate Amt" := 1.5;
        CurrencyExchangeRate.Insert();
        exit(Currency.Code);
    end;

    procedure SetInvoiceRounding(InvoiceRounding: Boolean)
    var
        SalesReceivablesSetup: Record "Sales & Receivables Setup";
    begin
        SalesReceivablesSetup.Get();
        SalesReceivablesSetup."Invoice Rounding" := InvoiceRounding;
        SalesReceivablesSetup.Modify();
    end;

    procedure SetInvRoundingPrecisionLCY(Precision: Decimal)
    var
        GeneralLedgerSetup: Record "General Ledger Setup";
    begin
        GeneralLedgerSetup.Get();
        GeneralLedgerSetup."Inv. Rounding Precision (LCY)" := Precision;
        GeneralLedgerSetup.Modify();
    end;

    procedure SetCopyCommentsOrderToInvoice(CopyComments: Boolean)
    var
        SalesReceivablesSetup: Record "Sales & Receivables Setup";
    begin
        SalesReceivablesSetup.Get();
        SalesReceivablesSetup."Copy Comments Order to Invoice" := CopyComments;
        SalesReceivablesSetup.Modify();
    end;

    procedure CreateSalesComment(DocumentNo: Code[20]; DocumentLineNo: Integer)
    var
        SalesCommentLine: Record "Sales Comment Line";
    begin
        SalesCommentLine.Init();
        SalesCommentLine."Document Type" := SalesCommentLine."Document Type"::Order;
        SalesCommentLine."No." := DocumentNo;
        SalesCommentLine."Document Line No." := DocumentLineNo;
        SalesCommentLine."Line No." := 10000;
        SalesCommentLine.Date := WorkDate();
        SalesCommentLine.Comment := 'Opmetrix test comment';
        SalesCommentLine.Insert();
    end;

    procedure CreateBankAccount(): Code[20]
    var
        BankAccount: Record "Bank Account";
        BankAccountPostingGroup: Record "Bank Account Posting Group";
    begin
        BankAccountPostingGroup.FindFirst();
        BankAccount.Init();
        BankAccount."No." := 'OPMB' + CopyStr(Any.AlphanumericText(5), 1, 5);
        BankAccount.Name := 'Opmetrix test bank';
        BankAccount.Insert(true);
        BankAccount.Validate("Bank Acc. Posting Group", BankAccountPostingGroup.Code);
        BankAccount.Modify(true);
        exit(BankAccount."No.");
    end;

    /// <summary>A cash receipt journal batch with one customer payment line for a new customer.</summary>
    procedure CreatePaymentLine(var GenJournalBatch: Record "Gen. Journal Batch"; var GenJournalLine: Record "Gen. Journal Line"; var CustomerNo: Code[20])
    var
        GenJournalTemplate: Record "Gen. Journal Template";
        Customer: Record Customer;
        SourceCode: Record "Source Code";
        GLAccount: Record "G/L Account";
        TemplateName: Code[10];
    begin
        CreatePostingSetup("Tax Calculation Type"::"Normal VAT");
        CreateCustomer(Customer);
        CustomerNo := Customer."No.";
        SourceCode.FindFirst();
        TemplateName := 'O' + CopyStr(Any.AlphanumericText(5), 1, 5);

        GenJournalTemplate.Init();
        GenJournalTemplate.Name := TemplateName;
        GenJournalTemplate.Type := GenJournalTemplate.Type::"Cash Receipts";
        GenJournalTemplate."Source Code" := SourceCode.Code;
        GenJournalTemplate.Insert();
        GenJournalBatch.Init();
        GenJournalBatch."Journal Template Name" := TemplateName;
        GenJournalBatch.Name := 'DEFAULT';
        GenJournalBatch.Insert();

        GenJournalLine.Init();
        GenJournalLine."Journal Template Name" := TemplateName;
        GenJournalLine."Journal Batch Name" := GenJournalBatch.Name;
        GenJournalLine."Line No." := 10000;
        GenJournalLine.Insert(true);
        GenJournalLine.Validate("Posting Date", WorkDate());
        GenJournalLine.Validate("Document Type", GenJournalLine."Document Type"::Payment);
        GenJournalLine.Validate("Document No.", 'OPMPAY' + CopyStr(Any.AlphanumericText(6), 1, 6));
        GenJournalLine.Validate("Account Type", GenJournalLine."Account Type"::Customer);
        GenJournalLine.Validate("Account No.", Customer."No.");
        GenJournalLine.Validate("Bal. Account Type", GenJournalLine."Bal. Account Type"::"G/L Account");
        GenJournalLine.Validate("Bal. Account No.", CreateGLAccount(GLAccount."Gen. Posting Type"::" ", false));
        GenJournalLine.Validate(Amount, -Any.DecimalInRange(100, 1000, 2));
        GenJournalLine.Modify(true);
    end;
}
#endif
