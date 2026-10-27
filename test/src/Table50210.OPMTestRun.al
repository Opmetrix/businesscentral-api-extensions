#if TESTAPP
/// <summary>One run of the test suite with code coverage. Created and started through the OPM test run API.</summary>
table 50210 "OPM Test Run"
{
    Caption = 'OPM Test Run';
    DataClassification = SystemMetadata;

    fields
    {
        field(1; "Entry No."; Integer) { AutoIncrement = true; DataClassification = SystemMetadata; }
        field(2; Status; Text[30]) { DataClassification = SystemMetadata; }
        field(3; "Started At"; DateTime) { DataClassification = SystemMetadata; }
        field(4; "Finished At"; DateTime) { DataClassification = SystemMetadata; }
        field(5; "Tests Total"; Integer) { DataClassification = SystemMetadata; }
        field(6; "Tests Passed"; Integer) { DataClassification = SystemMetadata; }
        field(7; "Tests Failed"; Integer) { DataClassification = SystemMetadata; }
        field(8; "Lines Total"; Integer) { DataClassification = SystemMetadata; }
        field(9; "Lines Covered"; Integer) { DataClassification = SystemMetadata; }
        field(10; "Coverage Pct"; Decimal) { DataClassification = SystemMetadata; DecimalPlaces = 0 : 2; }
        field(11; Message; Text[2048]) { DataClassification = SystemMetadata; }
        field(12; "Tracking Started"; Boolean) { DataClassification = SystemMetadata; } // not used any more
        field(13; "Wait For Exercise"; Boolean) { DataClassification = SystemMetadata; }
        field(14; "Exercise Done"; Boolean) { DataClassification = SystemMetadata; }
    }

    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
    }
}
#endif
