/// <summary>
/// Shared scenario builders for the Opmetrix extension tests.
/// </summary>
codeunit 50200 "OPM Test Helper"
{
    var
        LibrarySales: Codeunit "Library - Sales";
        LibraryERM: Codeunit "Library - ERM";
        LibraryRandom: Codeunit "Library - Random";
        Assert: Codeunit "Library Assert";
        LineGLAccount: Record "G/L Account";

    /// <summary>
    /// Creates an open sales order for a new customer, with G/L account lines and the posting setup needed for prepayments.
    /// All lines carry a positive unit price. The prepayment % is left at 0 on the header.
    /// </summary>
    procedure CreateOrder(var SalesHeader: Record "Sales Header"; LineCount: Integer; PricesIncludingVAT: Boolean)
    begin
        CreateOrderWithCurrency(SalesHeader, LineCount, PricesIncludingVAT, '');
    end;

    procedure CreateOrderWithCurrency(var SalesHeader: Record "Sales Header"; LineCount: Integer; PricesIncludingVAT: Boolean; CurrencyCode: Code[10])
    begin
        CreateOrderWithVATCalculation(SalesHeader, LineCount, PricesIncludingVAT, CurrencyCode, "Tax Calculation Type"::"Normal VAT");
    end;

    procedure CreateOrderWithVATCalculation(var SalesHeader: Record "Sales Header"; LineCount: Integer; PricesIncludingVAT: Boolean; CurrencyCode: Code[10]; VATCalculationType: Enum "Tax Calculation Type")
    var
        SalesLine: Record "Sales Line";
        i: Integer;
    begin
        LibrarySales.CreatePrepaymentVATSetup(LineGLAccount, VATCalculationType);
        LibrarySales.CreateSalesHeader(
          SalesHeader, SalesHeader."Document Type"::Order,
          LibrarySales.CreateCustomerWithBusPostingGroups(LineGLAccount."Gen. Bus. Posting Group", LineGLAccount."VAT Bus. Posting Group"));
        if CurrencyCode <> '' then
            SalesHeader.Validate("Currency Code", CurrencyCode);
        SalesHeader.Validate("Prices Including VAT", PricesIncludingVAT);
        SalesHeader.Validate("Posting Date", WorkDate());
        SalesHeader.Validate("Document Date", WorkDate());
        SalesHeader.Validate("Due Date", CalcDate('<30D>', WorkDate()));
        SalesHeader.Modify(true);

        for i := 1 to LineCount do begin
            LibrarySales.CreateSalesLine(
              SalesLine, SalesHeader, SalesLine.Type::"G/L Account", LineGLAccount."No.", LibraryRandom.RandIntInRange(1, 10));
            SalesLine.Validate("Unit Price", LibraryRandom.RandDecInRange(100, 1000, 2));
            SalesLine.Modify(true);
        end;
        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
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

    procedure LineGLAccountNo(): Code[20]
    begin
        exit(LineGLAccount."No.");
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
}
