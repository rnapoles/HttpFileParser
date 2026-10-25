unit TestFixtures;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
interface
uses Classes;

type
  TLevel = (lvLow, lvHigh);

  TAddress = class(TPersistent)
  private
    FCity: string;
  published
    property City: string read FCity write FCity;
  end;

  TPerson = class(TPersistent)
  private
    FName: string;
    FAge: Integer;
    FScore: Double;
    FActive: Boolean;
    FLevel: TLevel;
    FAddress: TAddress;
    FSecret: string;
    FNoAddress: TAddress;
  public
    constructor Create;
    destructor Destroy; override;
    property Secret: string read FSecret write FSecret; // public: not readable
  published
    property Name: string read FName write FName;
    property Age: Integer read FAge write FAge;
    property Score: Double read FScore write FScore;
    property Active: Boolean read FActive write FActive;
    property Level: TLevel read FLevel write FLevel;
    property Address: TAddress read FAddress;
    property NoAddress: TAddress read FNoAddress;
  end;

function NewPerson: TPerson; // Ann, 41, 2.5, active, lvHigh, lives in Lisbon

implementation

constructor TPerson.Create;
begin
  inherited Create;
  FAddress := TAddress.Create;
end;

destructor TPerson.Destroy;
begin
  FAddress.Free;
  inherited Destroy;
end;

function NewPerson: TPerson;
begin
  Result := TPerson.Create;
  Result.Name := 'Ann';
  Result.Age := 41;
  Result.Score := 2.5;
  Result.Active := True;
  Result.Level := lvHigh;
  Result.Address.City := 'Lisbon';
  Result.Secret := 'hidden';
end;

end.
