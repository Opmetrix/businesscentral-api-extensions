# Opmetrix Business Central API Extensions: test app

Separate AL test app for the extension in the repository root (ADO 1093446). It depends on the AU/NZ build of the extension and on
Microsoft's test libraries (Library Assert, Any, Application Test Library, Tests-TestLibraries).

| Object | What it tests |
|---|---|
| `Codeunit50200.OPMTestHelper.al` | Scenario builders (order with prepayment setup, API action wrapper) |
| `Codeunit50201.OPMPrepaymentsApiTests.al` | Prepayments API page 50125 and, through it, the posting flow of codeunit 50130 |
| `Codeunit50202.OPMPostPrepaymentsTests.al` | Public procedures of codeunit 50130 (`Post Prepayments`) |
| `Codeunit50203.OPMPaymentApiTests.al` | Customer payment journals page 50128 and customer payments page 50129 |
| `Codeunit50204.OPMSalesDocumentApiTests.al` | Sales header page 50139 and the sales invoice line part, page 50138 (through page 50137) |

The other pages and queries (50120 to 50124, 50126, 50127, 50130 to 50137 and the `Query*` objects) are declarative API
definitions with no executable statements, so they have nothing to cover.

## Layout: how the test folder is kept out of the extension build

The extension project is the repository root (`app.json`, `app-WW.json`), and the AL compiler includes every `.al` file below a
project folder, so `test/` is inside the extension's compile scope. To keep the test code out of the extension, every file in
`test/src` is wrapped in `#if TESTAPP ... #endif`. The extension builds (AU/NZ and worldwide) do not define `TESTAPP`, so they see
empty files and compile no test objects. Only this app defines it (`preprocessorSymbols` in `test/app.json`).

* New test files must start with `#if TESTAPP` and end with `#endif`, or the extension build will fail.
* The extension's `.app` still carries the text of these files in its bundled source (the extension's `app.json` sets
  `includeSourceInSymbolFile`), but no test objects are compiled into it.

## Running

```powershell
.\test\Run-Tests.ps1                 # needs Docker (Windows containers) and BcContainerHelper
```

The script creates a disposable AU sandbox container, compiles and publishes the extension and this app, runs the tests with code
coverage and fails when a test fails or coverage is below `-MinimumCoverage` (default 100). The same script runs in
`.github/workflows/test.yml` on pull requests.

The tests post documents and the code under test commits, so they cannot be rolled back. Never run them against a shared or
production environment.

## Status

* The test app compiles against the Business Central v29 AU symbols.
* **The tests have not been run and coverage has not been measured.** The machine this was written on has no Docker or Business
  Central container. The 100% target is therefore not yet proven. Run `Run-Tests.ps1` on a build agent, then fix failing
  scenario set-up and add tests for any lines the coverage report shows as missed.
* `Run-Tests.ps1` has the same caveat: parameter names may need adjusting for the installed BcContainerHelper version.

## Code that cannot reach 100% without agreement (exclusions)

The ticket says production code stays unchanged except for small changes needed to make a path testable, and those need to be
agreed first. These paths in `Codeunit50130.PostPrepayments.al` are unreachable today:

| Code | Why it cannot run |
|---|---|
| `Execute` credit memo case, `CreditMemo`, `Code(..., 1)` and every `DocumentType::"Credit Memo"` branch (`UpdateDocNos`, `InsertSalesCrMemoHeader`, `InsertSalesCrMemoLine`, `GetCalcPmtDiscOnCrMemos`, credit memo branches of `PostBalancingEntry`, `UpdatePostedSalesDocument`, `UpdateSalesDocument`, `CopyHeaderCommentLines`, `CopyLineCommentLines`, `GetCurrencyAmountRoundingPrecision`) | `SetDocumentType` is private and is only ever called with `Invoice` (in `PostPrepaymentInvoice`). No public entry point posts a prepayment credit memo. |
| `PreviewMode` branches (`Code`, `UpdateDocNos`) and `GenJnlPostPreview.ThrowError` | `PreviewMode` is never set to true. |
| `SuppressCommit` branch in `Code` | `SuppressCommit` is never set to true. |
| `Handled` checks in `Invoice` and `CreditMemo` | `Handled` is a local variable that is never set. |
| Last `exit(2)` in `PrepmtDocTypeToDocType` | Both option values return inside the `case`. |
| `PrepmtVATDiffAmount` and `PrepmtAmount` `else` branches | Only reached with document type credit memo. |
| `UpdateVATOnLines` zero `PrepmtAmtToInvTotal` branch and zero `Line Amount` branch | A line with a zero prepayment amount is skipped before it is reached. |

Options for these: (a) agree a small change that exposes a public `PostPrepaymentCreditMemo`, which makes the whole credit memo
path testable, and delete the dead preview, suppress-commit and handled code; or (b) keep them as listed exclusions.

Also not covered by this test app:

* `Page50139` `OnModifyRecord` change-of-id check: the platform rejects changes to `SystemId` before the trigger, so only the
  `No.` check is tested.
* `Page50138` error branches (`Id or Document Id` missing, aggregate not found, line not found): the sales invoice API always
  supplies a valid document id.
* `AdjustInvLineBuffers`/`InsertCorrInvLineBuffer` rounding-correction branches need a foreign-currency order whose LCY rounding
  differs between lines. These depend on exchange-rate data and should be added once a coverage run shows them as missed.
* The `#if BUILD_REGION_AUNZ` block in `CalcVATAmountLines` only exists in the AU/NZ build. The worldwide build
  (`app-WW.json`) is not covered by this app.
