#if TESTAPP
/// <summary>Read-only API page with the coverage of every executable line of the extension for each run.</summary>
page 50211 "OPM Coverage Lines API"
{
    PageType = API;
    APIPublisher = 'opmetrix';
    APIGroup = 'testing';
    APIVersion = 'v1.0';
    EntityName = 'coverageLine';
    EntitySetName = 'coverageLines';
    SourceTable = "OPM Coverage Line";
    ODataKeyFields = SystemId;
    Editable = false;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;
    Caption = 'coverageLines', Locked = true;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(id; Rec.SystemId) { Caption = 'id', Locked = true; }
                field(runEntryNo; Rec."Run Entry No.") { Caption = 'runEntryNo', Locked = true; }
                field(objectType; Rec."Object Type") { Caption = 'objectType', Locked = true; }
                field(objectId; Rec."Object ID") { Caption = 'objectId', Locked = true; }
                field(lineNo; Rec."Line No.") { Caption = 'lineNo', Locked = true; }
                field(lineText; Rec."Line Text") { Caption = 'lineText', Locked = true; }
                field(hits; Rec.Hits) { Caption = 'hits', Locked = true; }
            }
        }
    }
}
#endif
