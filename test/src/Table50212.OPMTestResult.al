#if TESTAPP
/// <summary>Result of one test method in the last run.</summary>
table 50212 "OPM Test Result"
{
    Caption = 'OPM Test Result';
    DataClassification = SystemMetadata;

    fields
    {
        field(1; "Entry No."; Integer) { AutoIncrement = true; DataClassification = SystemMetadata; }
        field(2; "Run Entry No."; Integer) { DataClassification = SystemMetadata; }
        field(3; "Codeunit ID"; Integer) { DataClassification = SystemMetadata; }
        field(4; "Codeunit Name"; Text[50]) { DataClassification = SystemMetadata; }
        field(5; "Function Name"; Text[128]) { DataClassification = SystemMetadata; }
        field(6; Result; Text[20]) { DataClassification = SystemMetadata; }
        field(7; "Error Message"; Text[2048]) { DataClassification = SystemMetadata; }
    }

    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
    }
}
#endif
