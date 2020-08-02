unit BarcodeHook;

interface

uses
  Windows, Messages, Classes, SysUtils;

var
  hook: HHOOK;

function KeyboardHook(nCode: Integer; wParamv: WPARAM; lParamv: LPARAM): LRESULT; stdcall;

type
  PKeyBoardHookStruct = ^RKeyBoardHookStruct;

  RKeyBoardHookStruct = record
    vkCode: DWORD; //������
    scanCode: DWORD; //ɨ����
    flags: DWORD;
    Time: DWORD;
    dwExtraInfo: DWORD;
  end;

     (*
     ����: ���ɨ��ǹ��ɨ�趯��.��ʹ���ǵĳ�����windows�ĵ�ǰ�����, Ҳ���Լ�ص�.
     ԭ��: ����Keyboard hook�ķ�ʽʵ�ּ��. ��ʵɨ��ǹɨ��Ĺ����൱�ڼ��̿�������һ������,���Ļس��൱��ɨ�����
           ���ڲ�������Ϣhook����, ��صĽ��������ٷְ�׼ȷ, ����Ϊ: ������ʱ���λ, ��ʱ���ظ�, ��ʱ�ᶪ��һλ
           ���׼ȷ��Ҫ���, �����ַ���:
               1.[��ʵ��]Ϊɨ��ǹ����ɨ��ǰ׺�ͺ�׺, ������֤, �����صĽ�����������ǰ׺/��׺, ��������ؽ��.
               2.[δʵ��]�������뱾�����֤�㷨, �Լ�صĽ��������֤
     ���Է���: ���û��ɨ��ǹ, ��ʹ�ô����ģ��, ������ʹ��С����.
     ʹ�÷���:
    FBarReader:=TBarcodeScanMonitor.GetInstance();
    FBarReader.RelayKeyPress:=True;//�����������, �Ƿ�Ҫ������������ʾ����
    FBarReader.BarcodeLengths:='3,4'; //������ܵĳ���
    FBarReader.ScanMaxDurationSecond:=10;//ɨ�����������ʱ
    FBarReader.AlwaysDuplicatedRead:=False; //��ֹ����ֵ�ظ�
    FBarReader.CheckPrefixStr:=''; //ǰ׺��֤��
    FBarReader.CheckSuffixStr:='';//��׺��֤��
    FBarReader.AutoRemoveCheckStr:=True;
    FBarReader.HookedThreadId:=0; //0ΪOS����ļ���hook
    FBarReader.OnScanFinished:=self.OnScanFinished1; //��һ��ɨ��������¼�
    if FBarReader.StartListenScan()=False then  //��ʼ��������
    begin
        Msg:= 'Barcode scanner failed to listen';
        Application.MessageBox(PChar(Msg),'Init failure',MB_OK+MB_ICONSTOP);
    end;
     *)

  TScanEvent = procedure(Sender: TObject; barcode: string) of object;

  TBarcodeScanMonitor = class(TObject)
  private
    FBarcodeSequence: string;
    FFirstKeyTime: TDateTime;
    FFstTick: Int64;
    FInputInterval: Integer;
    FFrontKeyTick: Int64;
    FStartRecordStrInout: Boolean;
    FScanFinished: TScanEvent;
    FRelayKeyPress: Boolean;
    FScanMaxDurationSecond: Double;
    FAlwayDuplicatedRead: Boolean;
    FHookThreadId: Integer;
    FAutoRemoveCheckStr: Boolean;
    FCheckSuffixStr: string;
    FCheckPrefixStr: string;
    FBarcodeLengths: string;
    FBarcodeLengthStrings: TStringList;
    FIsInListening: Boolean;
    //FUpperCase: Boolean; //�Ƿ�ʶ���д��ĸ
    //FLowerCase: Boolean; //�Ƿ�ʶ��Сд��ĸ
    //FNumber: Boolean; //�Ƿ��������
    //FOtherUseString: string; //������Ҫʶ����ַ�
    function Hook_Register(): Boolean;
    function Hook_Unregister(): Boolean;
    procedure ResetSession();
    procedure DoScanFinished();
    function KeyPressedByBarcodeDevice(vkCode: string): Boolean;
    function KeyPressedInUseCodeList(vkCode: string): Boolean; //���vkode�Ƿ�����Ҫ���ַ����б�����
    procedure SetUseOtherString(UseString: string);
    constructor Create();
    function RemoveDuplicated(barcode: string): string;
    function GetFirstKeyTime(): TDateTime;
    function CheckAndRemoveCheckStr(barcode: string): string;
    function ReadSingleKey(vkCode: string; var ByBarcodeDevice: Boolean): Boolean;
    procedure SetBarcodeLengths(const Value: string);
    function IsLegalLength(barcode: string): Boolean;
  public
    property OnScanFinished: TScanEvent read FScanFinished write FScanFinished;
    property RelayKeyPress: Boolean read FRelayKeyPress write FRelayKeyPress;
    property BarcodeLengths: string read FBarcodeLengths write SetBarcodeLengths;
    property ScanMaxDurationSecond: Double read FScanMaxDurationSecond write FScanMaxDurationSecond;
    property AlwaysDuplicatedRead: Boolean read FAlwayDuplicatedRead write FAlwayDuplicatedRead;
    property CheckPrefixStr: string read FCheckPrefixStr write FCheckPrefixStr;
    property CheckSuffixStr: string read FCheckSuffixStr write FCheckSuffixStr;
    property AutoRemoveCheckStr: Boolean read FAutoRemoveCheckStr write FAutoRemoveCheckStr;
    property HookedThreadId: Integer read FHookThreadId write FHookThreadId;
    property IsInListening: Boolean read FIsInListening;
    //property UseUpperCase: Boolean read FUpperCase write FUpperCase;
    //property UseLowerCase: Boolean read FLowerCase write FLowerCase;
    property InputInterval: Integer read FInputInterval write FInputInterval;
    //property UseNumber: Boolean read FNumber write FNumber;
    //property UseOtherString: string read FOtherUseString write SetUseOtherString;
    function StartListenScan(): Boolean;
    function StopListenScan(): Boolean;
    destructor Destroy(); override;
    class function GetInstance(): TBarcodeScanMonitor;
  end;

implementation

{ TBarcodeScanMonitor }
uses
  Unit1;

var
  Reader: TBarcodeScanMonitor = nil;

function KeyboardHook(nCode: Integer; wParamv: WPARAM; lParamv: LPARAM): LRESULT; stdcall;

  function EncodeUniCode(Str: WideString): string; //�ַ�����>PDU
  var
    i, len: Integer;
    cur: Integer;
  begin
    Result := '';
    len := Length(Str);
    i := 1;
    while i <= len do
    begin
      cur := Ord(Str[i]);
      Result := Result + IntToHex(cur, 4);
      Inc(i);
    end;
  end;

  function AcsiiToString(VKCodeAcsii: Integer): string;
  var
    StrArr: array[0..35] of string;
    AcsiiArr: array[0..35] of Integer;
    i: Integer;
  begin
    Result := '';
    case VKCodeAcsii of
      13:
        begin
          Result := '13';
          Exit;
        end;
      160:
        begin
          Result := '160';
          Exit;
        end;
      20:
        begin
          Result := '20';
          Exit;
        end;
      186:
        begin
          Result := ';';
          Exit;
        end;
      188:
        begin
          Result := ',';
          Exit;
        end;
      189:
        begin
          Result := '_';
          Exit;
        end;

    end;
    if ((VKCodeAcsii > 47) and (VKCodeAcsii < 58)) or ((VKCodeAcsii > 64) and (VKCodeAcsii < 91)) then
    begin
      Result := Char(VKCodeAcsii);
    end
    else
    begin
      Result := '';
    end;

  end;

var
  p: PKeyBoardHookStruct;
  key: string;
  handled: Boolean;
  ByBarcodeDevice: Boolean;
  Str1, Str2, Str3, Str4: string;
begin
  Result := 0; //if value is 1, means to stop to send out to other hooks
  //160=shift   20 =capslock
  handled := False;
  if (nCode = HC_ACTION) and (wParamv = WM_KEYDOWN) then
  begin
    p := PKeyBoardHookStruct(lParamv);
    //key := StringOfChar(Char(p^.vkCode), 1);
    key := AcsiiToString(p^.vkCode);
    //Form1.mmo1.Lines.Add('Acsii=' + IntToStr(p^.vkCode) + ' vkcode=' + key);
    Reader.ReadSingleKey(key, ByBarcodeDevice);

    {Reader.ReadSingleKey(key, ByBarcodeDevice);}

    if ByBarcodeDevice then
    begin
      handled := True;
      if Reader.RelayKeyPress then
        Result := CallNextHookEx(hook, nCode, wParamv, lParamv)
      else
        Result := 1;
    end;
  end;

  if handled = False then
    Result := CallNextHookEx(hook, nCode, wParamv, lParamv);
end;

function TBarcodeScanMonitor.CheckAndRemoveCheckStr(barcode: string): string;
var
  TempBarcode, EndStr: string;
begin
  TempBarcode := barcode;

  if FCheckPrefixStr <> '' then
    //check by FCheckPrefixStr
    if Pos(FCheckPrefixStr, TempBarcode) <> 1 then
    begin
      Result := ''; //check fail
      Exit;
    end;

  TempBarcode := Copy(TempBarcode, Length(FCheckPrefixStr) + 1, Length(TempBarcode));
  if FCheckSuffixStr = '' then
  begin
    if FAutoRemoveCheckStr then
      Result := TempBarcode
    else
      Result := barcode;
    Exit;
  end;

    //Check by FCheckSuffixStr
  if Length(TempBarcode) <= Length(FCheckSuffixStr) then
  begin
    Result := ''; //check failed
    Exit;
  end
  else
  begin
    EndStr := Copy(TempBarcode, Length(TempBarcode) - Length(FCheckSuffixStr) + 1, Length(FCheckSuffixStr));
    if EndStr <> FCheckSuffixStr then
    begin
      Result := ''; //check error
      Exit;
    end
    else
    begin
      TempBarcode := Copy(TempBarcode, 1, Length(TempBarcode) - Length(FCheckSuffixStr));
      if FAutoRemoveCheckStr then
        Result := TempBarcode
      else
        Result := barcode;
    end;
  end;

end;

constructor TBarcodeScanMonitor.Create;
begin
  FBarcodeLengthStrings := TStringList.Create;
  FRelayKeyPress := True;
  FScanMaxDurationSecond := 1.0;
  FHookThreadId := 0; //Windows OS level hook
  FAlwayDuplicatedRead := True;
  FCheckSuffixStr := '';
  FCheckPrefixStr := '';
  FAutoRemoveCheckStr := True;
  FInputInterval := 1000;
  Self.BarcodeLengths := '3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,80,81,82,83';

end;

destructor TBarcodeScanMonitor.Destroy;
begin
  FBarcodeLengthStrings.Free;
  Self.StopListenScan();
  inherited;
end;

procedure TBarcodeScanMonitor.DoScanFinished;
var
  barcode: string;
begin

  if Assigned(Self.FScanFinished) then
  begin
    barcode := Self.FBarcodeSequence;
    Self.ResetSession();
    barcode := RemoveDuplicated(barcode);
    if Self.IsLegalLength(barcode) then
    begin
      barcode := CheckAndRemoveCheckStr(barcode);
      if Self.IsLegalLength(barcode) then
        Self.FScanFinished(Self, barcode);
    end;
  end;
  Self.ResetSession;
end;

function TBarcodeScanMonitor.GetFirstKeyTime: TDateTime;
begin
  if Self.FBarcodeSequence = '' then
    Result := Now()
  else
    Result := Self.FFirstKeyTime;

end;

class function TBarcodeScanMonitor.GetInstance: TBarcodeScanMonitor;
begin
  if Reader = nil then
    Reader := TBarcodeScanMonitor.Create();

  Result := Reader;
end;

function TBarcodeScanMonitor.Hook_Register: Boolean;
const
  WH_KEYBOARD_LL: Integer = 13;
var
  tid: Integer;
begin
  tid := Self.HookedThreadId; //GetCurrentThreadId()

    //��4������Ϊ0, ��ʾȫ�ֹ���
  hook := SetWindowsHookEx(WH_KEYBOARD_LL, @KeyboardHook, HInstance, tid);
  Result := (hook <> 0);
end;

function TBarcodeScanMonitor.Hook_Unregister: Boolean;
begin
  if hook <> 0 then
    UnhookWindowsHookEx(hook);
  Result := True;
end;

function TBarcodeScanMonitor.KeyPressedByBarcodeDevice(vkCode: string): Boolean;
var
  Time: Single;
begin
  Result := True;
//  if ((vkCode < #48) and (vkCode <> #13)) or (vkCode > #57) or (Now() - GetFirstKeyTime() > FScanMaxDurationSecond / (3600 * 24)) or ((vkCode = #13) and (Self.IsLegalLength(Self.FBarcodeSequence) = False)) then
//  begin
//    Result := False;
//  end;
  {�������ϵͳ�涨���ַ����������棬�Ҳ��ǻس�������ʱ���ǻس��������ݳ��ȳ��ˣ����ж���������ʶ��}
//  if ((not KeyPressedInUseCodeList(vkCode)) and ({vkCode <> #13}(vkCode <> '13') or (vkCode <> #$D))) or (Now() - GetFirstKeyTime() > FScanMaxDurationSecond / (3600 * 24)) or ((vkCode = '13') and (Self.IsLegalLength(Self.FBarcodeSequence) = False)) then
//  begin
//    Result := False;
//  end;

  //Form1.mmo1.Lines.Add(IntToStr(GetTickCount64));
  //Form1.mmo1.Lines.Add(IntToStr(Self.FFstTick));
  Form1.mmo1.Lines.Add('interval=' + IntToStr(GetTickCount64 - Self.FFstTick));
//  Time := FScanMaxDurationSecond / (3600 * 24);
//  Form1.mmo1.Lines.Add(FloatToStr(Time));
  if ((GetTickCount64 - Self.FFstTick > InputInterval){ or (Self.IsLegalLength(Self.FBarcodeSequence) = False)}) then
  begin
    Result := False;
    //Form1.mmo1.Lines.Add('false');
  end;
//  if ((Now() - GetFirstKeyTime() > FScanMaxDurationSecond / (3600 * 24)) or ((vkCode = '13') and (Self.IsLegalLength(Self.FBarcodeSequence) = False))) then
//  begin
//    Result := False;
//    //Form1.mmo1.Lines.Add('false');
//  end;
end;

function TBarcodeScanMonitor.KeyPressedInUseCodeList(vkCode: string): Boolean;
var
  UpperCheck, LowerCheck, NumberCheck, OtherStrCheck: Boolean;
begin
  Result := False;

end;

function TBarcodeScanMonitor.ReadSingleKey(vkCode: string; var byBarcodeDevice: Boolean): Boolean;
var
  StrInputTime: TDateTime;
  Temp: Int64;
begin
  Result := True;
  byBarcodeDevice := True;
  if Self.FBarcodeSequence = '' then
  begin
    Self.FFirstKeyTime := Now();
    Self.FFstTick := GetTickCount64;
  end;

  //Form1.mmo1.Lines.Add(vkCode);
  if Self.FStartRecordStrInout then
  begin
    if (vkCode = '13') then
    begin
      Form1.mmo1.Lines.Add('interval=' + IntToStr(GetTickCount64 - Self.FFstTick));
      if (GetTickCount64 - Self.FFstTick > InputInterval) {and (Length(Self.FBarcodeSequence) < 18)} then
      begin
        Self.ResetSession();
        byBarcodeDevice := False;
        Exit;
      end
      else
      begin
        Form1.mmo1.Lines.Add('���ɨ��=' + Self.FBarcodeSequence);
        Self.DoScanFinished();
        Exit;
      end;
    end;
  end;

  if not ((vkCode = '160') or (vkCode = '20')) then
  begin
    if KeyPressedByBarcodeDevice(vkCode) = False then
    begin
      Self.ResetSession();
      byBarcodeDevice := False;
      Exit;
    end
  end
  else
  begin
    vkCode := '';
  end;

  Self.FFrontKeyTick := GetTickCount;
  if not Self.FStartRecordStrInout then
  begin
    Self.FStartRecordStrInout := True;
  end;
  Self.FBarcodeSequence := Self.FBarcodeSequence + vkCode;
  Exit;
  //  if (vkCode = #13) or (vkCode = #$D) then //finished
//  begin
//
//    Form1.mmo1.Lines.Add('���ɨ��=' + vkCode);
//    Self.DoScanFinished();
//  end
//  else
//  begin
//    if Self.FBarcodeSequence = '' then
//      Self.FFirstKeyTime := Now();
//    Self.FFrontKeyTick := GetTickCount;
//    if not Self.FStartRecordStrInout then
//    begin
//      Self.FStartRecordStrInout := True;
//    end;
//    Self.FBarcodeSequence := Self.FBarcodeSequence + vkCode;
//    Exit;
//  end;
end;

function TBarcodeScanMonitor.RemoveDuplicated(barcode: string): string;
var
  str1, str2: string;
  i: Integer;
begin
  Result := barcode;
  str1 := '';
  str2 := '';
  if FAlwayDuplicatedRead then //if duplicated , remove duplicated
  begin
    if (Length(barcode) mod 2) = 0 then
    begin
      for i := 1 to (Length(barcode) div 2) do
      begin
        str1 := str1 + barcode[i * 2 - 1];
        str2 := str2 + barcode[i * 2];
        if str2 = str1 then
          Result := str1;
      end;
    end;

  end;

end;

procedure TBarcodeScanMonitor.ResetSession;
begin
  FBarcodeSequence := '';
  FFrontKeyTick := 0;
  Form1.mmo1.Lines.Add('initial OK');
  FStartRecordStrInout := False;
  FFstTick := 0;
end;

procedure TBarcodeScanMonitor.SetBarcodeLengths(const Value: string);
var
  i: Integer;
  list: TStringList;
begin
  FBarcodeLengths := Value;
  FBarcodeLengthStrings.Text := '';
  list := TStringList.Create;
  list.DelimitedText := Value;
  list.Delimiter := ',';
  for i := 0 to list.Count - 1 do
    FBarcodeLengthStrings.Add(Trim(list.Strings[i]));
  list.Free;
end;

procedure TBarcodeScanMonitor.SetUseOtherString(UseString: string);
//var
//  i: Integer;
//  StrTemp: string;
begin
//{�û���Ҫ���һЩ��Ҫʶ��������ַ���������ȥ�޳����ִ�Сд��ĸ����Ϊʹ���ַ�����}
//  UseString := Trim(UseString);
//  StrTemp := '';
//  UseString := StringReplace(UseString, ' ', '', [rfReplaceAll]);
//  for i := 0 to Length(UseString) - 1 do
//  begin
//    if not (UseString[i] in ['a'..'z', '0'..'9', 'A'..'Z']) then
//    begin
//      StrTemp := StrTemp + UseString[i];
//    end;
//
//  end;
//  FOtherUseString := StrTemp;
end;

function TBarcodeScanMonitor.IsLegalLength(barcode: string): Boolean;
var
  i: Integer;
  len: string;
begin
  Result := True;
  Exit;
  Result := False;
  len := IntToStr(Length(barcode));

  for i := 0 to FBarcodeLengthStrings.Count - 1 do
  begin
    if len = FBarcodeLengthStrings.Strings[i] then
    begin
      Result := True;
      Break;
    end;
  end;

end;

function TBarcodeScanMonitor.StartListenScan: Boolean;
begin
  Result := FIsInListening;

  if Result = False then
    Result := Self.Hook_Register();

  FIsInListening := Result;
end;

function TBarcodeScanMonitor.StopListenScan: Boolean;
begin
  FIsInListening := False;
  Result := Self.Hook_Unregister();
end;

end.

