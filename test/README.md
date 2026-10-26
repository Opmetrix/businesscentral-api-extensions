# Opmetrix Business Central API Extensions: test app

Separate AL test app for the extension in the repository root (ADO 1093446). It depends on the AU/NZ build of the extension and on
three Microsoft apps that an online sandbox already has: Any, Library Assert and Test Runner. It uses no other test libraries, so it
can be published to a Business Central online sandbox without Docker.

## Measuring code coverage

```powershell
az login --tenant 43e728f5-a0d9-484d-9971-db0137ca2c70     # once
.\test\Measure-Coverage.ps1                                 # builds, publishes, runs the tests, reports coverage
.\test\Measure-Coverage.ps1 -MinimumCoverage 80             # fail below 80 %
```

`Measure-Coverage.ps1` needs the Azure CLI and the AL Language extension for VS Code (for `alc.exe`). It:

1. downloads the symbol packages from the sandbox and compiles the extension and this app,
2. publishes both to the `Sandbox` environment (the same request VS Code makes on F5),
3. starts a run through this app's API (`opmetrix/testing/v1.0`). The run turns on code coverage tracking for all sessions,
   waits while the script calls the extension's own OData endpoints (so page triggers that only run over OData are counted),
   then runs every test with Microsoft's test runner,
4. writes `coverage-summary.md`, `coverage-report.json`, `uncovered-lines.csv` and `test-results.csv` to `output-coverage/`.

The tests post prepayment invoices and payments, create customers and G/L accounts, and the API exercise posts one sales invoice,
so run it only against a sandbox you can throw away. The test set-up creates its own posting groups and, if they are empty, the
prepayment number series in Sales & Receivables Setup (Posted Prepmt. Inv. Nos. and Posted Prepmt. Cr. Memo Nos.).

| Object | What it is |
|---|---|
| `Codeunit50200.OPMTestHelper.al` | Scenario builders: posting groups, G/L accounts, customer, order, currency, journal |
| `Codeunit50201.OPMPrepaymentsApiTests.al` | Prepayments API page 50125 and, through it, the posting flow of codeunit 50130 |
| `Codeunit50202.OPMPostPrepaymentsTests.al` | Public procedures of codeunit 50130 (`Post Prepayments`) |
| `Codeunit50203.OPMPaymentApiTests.al` | Customer payment journals page 50128 and customer payments page 50129 (actions) |
| `Codeunit50204.OPMSalesDocumentApiTests.al` | Sales header page 50139 actions |
| `Codeunit50230.OPMSmokeTests.al` | One test that needs no data; proves the runner works |
| `Codeunit50210`, `Table50210` to `50212`, `Page50210` to `50212` | The runner: runs the tests, tracks coverage and exposes results through the API |

The pages and queries 50120 to 50124, 50126, 50127, 50130 to 50137 and `Query*` are declarative API definitions with no
executable statements, so they have nothing to cover.

## Layout: how the test folder is kept out of the extension build

The extension project is the repository root (`app.json`, `app-WW.json`), and the AL compiler includes every `.al` file below a
project folder, so `test/` is inside the extension's compile scope. To keep the test code out of the extension, every file in
`test/src` is wrapped in `#if TESTAPP ... #endif`. The extension builds (AU/NZ and worldwide) do not define `TESTAPP`, so they see
empty files and compile no test objects. Only this app defines it (`preprocessorSymbols` in `test/app.json`).

* New test files must start with `#if TESTAPP` and end with `#endif`, or the extension build will fail.
* The extension's `.app` still carries the text of these files in its bundled source (the extension's `app.json` sets
  `includeSourceInSymbolFile`), but no test objects are compiled into it.

## Current result (sandbox, Business Central 29)

54 tests, all passing. **Line coverage 80.77 % (588 of 728 executable lines).**

| Object | Lines | Covered | % |
|---|---:|---:|---:|
| Page 50125 Prepayments | 45 | 45 | 100 |
| Page 50128 Cust. Paym. Journals | 17 | 17 | 100 |
| Page 50129 CustomerPayments | 5 | 5 | 100 |
| Codeunit 50130 Post Prepayments | 606 | 473 | 78.1 |
| Page 50138 Sales Invoice Line Extension | 36 | 31 | 86.1 |
| Page 50139 Sales Header Extension | 19 | 17 | 89.5 |

## The remaining 140 lines (why it is not 100 %)

The ticket says production code stays unchanged except for small changes needed to make a path testable, and those need to be
agreed first. All of these are unreachable today:

| Code | Lines | Why it cannot run |
|---|---:|---|
| Prepayment credit memo: `Execute` credit memo case, `CreditMemo`, `Code(..., 1)`, `UpdateDocNos`, `InsertSalesCrMemoHeader`, `InsertSalesCrMemoLine`, `GetCalcPmtDiscOnCrMemos`, credit memo branches of `PostBalancingEntry`, `UpdatePostedSalesDocument`, `UpdateSalesDocument`, `CopyHeaderCommentLines`, `CopyLineCommentLines`, `InsertExtendedText`, `GetCurrencyAmountRoundingPrecision`, `PrepmtDocTypeToDocType` | about 105 | `SetDocumentType` is private and is only ever called with `Invoice` (in `PostPrepaymentInvoice`). No public entry point posts a prepayment credit memo. |
| `AdjustInvLineBuffers` correction branches, `InsertCorrInvLineBuffer`, credit memo part of `CalcPrepmtAmtInvLCYInLines` | about 20 | The VAT adjustment is only calculated for credit memos, so an invoice never reaches these lines. |
| Preview mode (`PreviewMode`, `GenJnlPostPreview.ThrowError`, `'***'` numbers) and the `Handled` checks | about 8 | `PreviewMode` is never set to true and `Handled` is never set. |
| `UpdateVATOnLines` branches for a zero prepayment amount, a zero VAT base and a zero invoice discount base; `RoundAmounts` line with equal `Amount` and `Amount Incl. VAT` in a foreign currency | about 7 | Lines with a zero prepayment amount are skipped before these lines; the other branches need VAT set-ups that are not reachable from the API. |
| Page 50139 `OnModifyRecord` id and number errors | 2 | The platform rejects a change of `SystemId` or `No.` before the trigger runs. |
| Page 50138 error branches (aggregate, line or document id missing) | 4 | The sales invoice API always supplies valid ids. |

Options: (a) agree a small change that exposes a public `PostPrepaymentCreditMemo`, which makes the credit memo path testable (about
125 more lines), and delete the dead preview, suppress-commit and handled code, or (b) keep the list above as the documented
exclusions.

## Not done yet

* **CI.** There is no pipeline that runs the tests and fails the build on a test failure. `Measure-Coverage.ps1` exits with
  code 1 on a test failure or when coverage is below `-MinimumCoverage`, so it can be used as the build step, but running it on a
  build agent needs a service account (not a personal login) that can publish to the sandbox.
* **Zero-priced lines.** An order with a zero-priced line (for example a free item) makes the prepayments API fail with "Line Amount
  Excl. VAT must have a value", because `UpdateSalesOrderPrepaymentFields` validates the prepayment amount of every line with a
  quantity. That is existing behaviour, not covered by a test.
