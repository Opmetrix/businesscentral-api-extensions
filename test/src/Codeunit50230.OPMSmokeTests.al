#if TESTAPP
/// <summary>Minimal test that needs no test libraries; proves the runner and coverage pipeline end to end.</summary>
codeunit 50230 "OPM Smoke Tests"
{
    Subtype = Test;

    var
        Assert: Codeunit "Library Assert";

    [Test]
    procedure InvoiceRoundingAccountIsReturnedForCustomerPostingGroup()
    var
        CustomerPostingGroup: Record "Customer Posting Group";
        PostPrepayments: Codeunit "Post Prepayments";
    begin
        CustomerPostingGroup.SetFilter("Invoice Rounding Account", '<>%1', '');
        CustomerPostingGroup.FindFirst();

        Assert.AreEqual(
          CustomerPostingGroup."Invoice Rounding Account",
          PostPrepayments.GetInvRoundingAccNo(CustomerPostingGroup.Code), 'Invoice rounding account');
    end;
}
#endif
