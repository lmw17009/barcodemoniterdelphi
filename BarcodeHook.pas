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
    vkCode: DWORD; //虚拟码
    scanCode: DWORD; //扫描码
    flags: DWORD;
    Time: DWORD;
    dwExtraInfo: DWORD;
  end;

     (*
     功能: 监控扫描枪的扫描动作.即使我们的程序不是windows的当前活动程序, 也可以监控到.
     原理: 采用Keyboard hook的方式实现监控. 其实扫描枪扫描的过程相当于键盘快速输入一段文字,最后的回车相当于扫描结束
           由于采用了消息hook机制, 监控的结果并不会百分百准确, 表现为: 数字有时会错位, 有时会重复, 有时会丢掉一位
           如果准确度要求高, 有两种方法:
               1.[已实现]为扫描枪设置扫描前缀和后缀, 用作验证, 如果监控的结果不包含这对前缀/后缀, 即舍弃监控结果.
               2.[未实现]根据条码本身的验证算法, 对监控的结果进行验证
     测试方法: 如果没有扫描枪, 可使用大键盘模拟, 但不能使用小键盘.
     使用方法:
    FBarReader:=TBarcodeScanMonitor.GetInstance();
    FBarReader.RelayKeyPress:=True;//按键被捕获后, 是否要继续将按键显示出来
    FBarReader.BarcodeLengths:='3,4'; //条码可能的长度
    FBarReader.ScanMaxDurationSecond:=10;//扫描条码的最大耗时
    FBarReader.AlwaysDuplicatedRead:=False; //防止条码值重复
    FBarReader.CheckPrefixStr:=''; //前缀验证码
    FBarReader.CheckSuffixStr:='';//后缀验证码
    FBarReader.AutoRemoveCheckStr:=True;
    FBarReader.HookedThreadId:=0; //0为OS级别的键盘hook
    FBarReader.OnScanFinished:=self.OnScanFinished1; //绑定一个扫描结束的事件
    if FBarReader.StartListenScan()=False then  //开始监听键盘
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
    //FUpperCase: Boolean; //是否识别大写字母
    //FLowerCase: Boolean; //是否识别小写字母
    //FNumber: Boolean; //是否包含数字
    //FOtherUseString: string; //其他需要识别的字符
    function Hook_Register(): Boolean;
    function Hook_Unregister(): Boolean;
    procedure ResetSession();
    procedure DoScanFinished();
    function KeyPressedByBarcodeDevice(vkCode: string): Boolean;
    function KeyPressedInUseCodeList(vkCode: string): Boolean; //检测vkode是否在需要的字符串列表里面
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

  function EncodeUniCode(Str: WideString): string; //字符串－>PDU
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

    //第4个参数为0, 表示全局钩子
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
  {如果不在系统规定的字符串集合里面，且不是回车键，超时，是回车键但数据长度超了，就判断数据数据识别}
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
        Form1.mmo1.Lines.Add('完成扫描=' + Self.FBarcodeSequence);
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
//    Form1.mmo1.Lines.Add('完成扫描=' + vkCode);
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
//{用户需要添加一些需要识别的特殊字符，此属性去剔除数字大小写字母后作为使用字符集合}
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

