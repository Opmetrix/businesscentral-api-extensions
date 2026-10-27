#if TESTAPP
/// <summary>Executable line of an extension object with its number of hits in the last run.</summary>
table 50211 "OPM Coverage Line"
{
    Caption = 'OPM Coverage Line';
    DataClassification = SystemMetadata;

    fields
    {
        field(1; "Entry No."; Integer) { AutoIncrement = true; DataClassification = SystemMetadata; }
        field(2; "Run Entry No."; Integer) { DataClassification = SystemMetadata; }
        field(3; "Object Type"; Text[20]) { DataClassification = SystemMetadata; }
        field(4; "Object ID"; Integer) { DataClassification = SystemMetadata; }
        field(5; "Line No."; Integer) { DataClassification = SystemMetadata; }
        field(6; "Line Text"; Text[250]) { DataClassification = SystemMetadata; }
        field(7; Hits; Integer) { DataClassification = SystemMetadata; }
    }

    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
    }
}
#endif
