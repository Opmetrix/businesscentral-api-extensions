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
| `Codeunit50205.OPMPrepaymentCreditMemoTests.al` | Prepayment credit memo flow of codeunit 50130 (via the new `PostPrepaymentCreditMemo`) |
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

66 tests, all passing. **Line coverage 96.05 % (706 of 735 executable lines).**

| Object | Lines | Covered | % |
|---|---:|---:|---:|
| Page 50125 Prepayments | 45 | 45 | 100 |
| Page 50128 Cust. Paym. Journals | 17 | 17 | 100 |
| Page 50129 CustomerPayments | 5 | 5 | 100 |
| Codeunit 50130 Post Prepayments | 613 | 591 | 96.4 |
| Page 50138 Sales Invoice Line Extension | 36 | 31 | 86.1 |
| Page 50139 Sales Header Extension | 19 | 17 | 89.5 |

`PostPrepaymentCreditMemo` was added to codeunit 50130 for this (see below); without it the prepayment credit memo path cannot be
started and coverage stays at about 81 %.

## The remaining 29 lines

| Code | Lines | Why it is not covered |
|---|---:|---|
| Preview mode: `GenJnlPostPreview.ThrowError` and the two `'***'` document numbers in `UpdateDocNos` | 3 | `PreviewMode` is never set to true. |
| `AdjustInvLineBuffers` and `InsertCorrInvLineBuffer` correction branches | 15 | They run only when the rounded local currency amounts of the prepayment lines differ from the total by more than a rounding amount. Not reached with the exchange rates used; needs a purpose built rate and amounts. |
| `PrepmtDocTypeToDocType` final `exit(2)` | 1 | Both option values return inside the `case`. |
| `UpdateVATOnLines`: zero prepayment amount (2 lines), zero VAT base, zero invoice discount base | 4 | Lines with a zero prepayment amount are skipped before these lines; the others need VAT set-ups not reachable from the API. |
| `RoundAmounts`: equal `Amount` and `Amount Incl. VAT` in a foreign currency | 1 | Needs a 0 % VAT line in a foreign currency. |
| `PostBalancingEntry`: customer ledger entry with amount 0 | 1 | Not reachable. |
| Page 50139 `OnModifyRecord` id and number errors | 2 | The platform rejects a change of `SystemId` or `No.` before the trigger runs. |
| Page 50138: aggregate, line or document id missing (4 lines), id filter | 5 | The sales invoice API always supplies valid ids. |

## Production change made for the tests

`Codeunit50130.PostPrepayments.al` has one added public procedure, `PostPrepaymentCreditMemo`, which mirrors
`PostPrepaymentInvoice` (it sets the document type to credit memo and runs the codeunit). The credit memo code in the codeunit
already existed but nothing could start it. No existing behaviour changed. Nothing in the extension calls the new procedure; remove
it (and `test/src/Codeunit50205.OPMPrepaymentCreditMemoTests.al`) if you do not want it in the extension.

## Not done yet

* **CI.** There is no pipeline that runs the tests and fails the build on a test failure. `Measure-Coverage.ps1` exits with
  code 1 on a test failure or when coverage is below `-MinimumCoverage`, so it can be used as the build step, but running it on a
  build agent needs a service account (not a personal login) that can publish to the sandbox.
* **Zero-priced lines.** An order with a zero-priced line (for example a free item) makes the prepayments API fail with "Line Amount
  Excl. VAT must have a value", because `UpdateSalesOrderPrepaymentFields` validates the prepayment amount of every line with a
  quantity. That is existing behaviour, not covered by a test.
