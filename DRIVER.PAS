{$G+}
Unit Driver;

Interface

Type
  TPoint = record { Точка в экранных координатах }
    X,Y:integer;
  end;
  TRect = record  { Прямоугольник на экране }
    Case boolean of
      true:  (Left,Top, Right,Bottom:integer;);
      false: (A,B:TPoint;);
  end;
Type
  TEventKind = word; { Вид события }
Const { Виды событий и их маски (поле TEvent.What) }
  evNothing  = $0000; { Пустое событие - ничего не произошло }
  evKeyDown  = $0001;  evKeyUp = $0002; { Клавиатурные события }
  evMouseMove = $0004; { Мышиные события - движение мыши }
  evLButtonDown = $0008;  evLButtonUp = $0010; { Левая кнопка мыши }
  evRButtonDown = $0020;  evRButtonUp = $0040; { Правая кнопка мыши }
  evTimer    = $0100; { Событие о срабатывании заказанного таймера }
  evMouse    = $007C; { Маска мышиных событий }
  evKeyboard = $0003; { Маска клавиатурных событий }
  evAll      = $FFFF; { Маска всех событий }
Type
  TEvent = record { Внешнее событие }
    Case What:TEventKind of { Что произошло (см. константы evXxx) }
      evNothing: ();
      evKeyDown,evKeyUp: (
            Auto:boolean; { Признак автоповтора }
            Case byte of
              0: (Symbol: char; Scan:byte);
              1: (KeyCode:word)); { см. константы kbXxx }
      evMouseMove, evLButtonDown, evLButtonUp,
          evRButtonDown, evRButtonUp: (Where:TPoint);
      evTimer:   (Timer:byte; { Номер таймера - число, выдаваемое MakeTimer }
                  Precision:boolean; { Признак точности события }
                  Lost:integer); { Число потеряных событий этого таймера }
  end;

  procedure InitDriver; { Инициализация драйвера }
  procedure DoneDriver; { Завершение работы драйвера }
  procedure GetNextEvent(var Event:TEvent);
  procedure KillEvents(AWhat:TEventKind); { Чистка очереди событий }
 { Мышь }
  procedure ShowMouse;
  procedure HideMouse;
  procedure SetMousePos(X,Y:integer);
 { Таймер }
  function  MakeTimer(Time:longint):byte; { Интервал Time изм-ся в сек/10 }
  procedure KillTimer(Timer:byte);        { Удаление таймера }

{  procedure PhantomKeyDown(KeyCode:word);}
  procedure PhantomTrackMouse(Target:TPoint);
{  procedure PhantomClick;}

Const { Расширенные коды клавиш (см. TEvent.KeyCode) }
  kbEnter     = $1C0D;  kbSpace     = $3920;  kbConsole   = $2960;
  kbGrayMult  = $372A;  kbGrayDiv   = 13568;  kbGrayEnter = $E00D;
  
  kbRShift    = 13824;  kbLShift    = 10752;
  kbCtrl      =  7424;  kbAlt       = 14336;
  
  kbNum1      = $0231;  kbNum2      = $0332;  kbNum3      =  1075;
  kbNum4      =  1332;  kbNum5      =  1589;  kbNum6      =  1846;
  kbNum7      =  2103;  kbNum8      =  2360;  kbNum9      =  2617;
  kbNum0      =  2864;  kbGrayNum1  = 20273;  kbGrayNum2  = 20530;
  kbGrayNum3  = 20787;  kbGrayNum4  = 19252;  kbGrayNum5  = 19509;
  kbGrayNum6  = 19766;  kbGrayNum7  = 18231;  kbGrayNum8  = 18488;
  kbGrayNum9  = 18745;  kbGrayNum0  = 21040;  kbGrayPoint = 21294;

  kbNoKey     = $0000;  kbEsc       = $011B;
  kbBack      = $0E08;  kbTab       = $0F09;
  kbF1        = $3B00;  kbF2        = $3C00;  kbF3        = $3D00;
  kbF4        = $3E00;  kbF5        = $3F00;  kbF6        = $4000;
  kbF7        = $4100;  kbF8        = $4200;  kbF9        = $4300;
  kbF10       = $4400;  kbF11       = $8500;  kbF12       = $8600;
  kbHome      = $4700;  kbUp        = $4800;  kbPgUp      = $4900;
  kbGrayMinus = $4A2D;  kbLeft      = $4B00;  kbRight     = $4D00;
  kbGrayPlus  = 20011;  kbEnd       = $4F00;  kbDown      = $5000;
  kbPgDn      = $5100;  kbIns       = $5200;  kbDel       = $5300;

Const
  ButtonCount:byte = 0;
Var
  MousePos:TPoint; { Положение мыши. Для изменения исп-ть SetMousePos }

{ Знак числа X }
Function Sign(X:integer):integer;


Implementation
  Uses Dos;

Const EventQueueSize = 30;
Var EventQueue:array [1..EventQueueSize] of TEvent;
  EventFirst:integer; { Индекс первого события в очереди }
  EventNext:integer;  { Индекс в очереди для помещения очередного события }
                      { EventFirst = EventNext => очередь пуста }
  MouseButtons:byte;
Const
  MouseEvents:boolean = false;
  KeyboardEvents:boolean = false;
  PrevKeyboardKeeper:pointer = nil;

Type
  TTimer = record
    Interval:longint;   { Интервал таймера, сек/10. Равен 0 => неисп-ся }
    StartTicks:longint; { Момент начала отсчета в тиках }
    LastTicks:longint;  { Момент появления последнего события этого таймера }
  end;
Const MaxTimers = 10;
Var Timers:array [1..MaxTimers] of TTimer;
  Ticks:longint absolute $0040:$006C;

Procedure RegisterNewEvent(var Event:TEvent);
Var Next:integer;
Begin
 { Вычисление индекса следующего события }
  Next := EventNext + 1;
  If Next > EventQueueSize then
    Next := 1;
 { Проверка на переполнение очереди }
  If Next <> EventFirst then begin { Это событие влезет в очередь }
    EventQueue[EventNext] := Event;
    EventNext := Next;
  end;
End;

Procedure KillEvents(AWhat:TEventKind); { Чистка очереди событий }
Var I:integer; First:integer;
Begin
  First := EventFirst;
  While First <> EventNext do with EventQueue[First] do begin
    If What and AWhat <> 0 then { Это то, что мы ищем }
      What := evNothing; { Зануляем найденное событие }
    Inc(First);
    If First > EventQueueSize then First := 1;
  end;
End;

Const MouseEvent:TEvent = (What:evMouseMove);
Var   MouseWhat:byte;

Procedure MouseProc;
Begin
  MousePos := MouseEvent.Where;
  If (MouseWhat and 1) <> 0 then begin { Особая обработка для evMouseMove }
    MouseEvent.What := evMouseMove;
    RegisterNewEvent(MouseEvent);
    MouseWhat := MouseWhat and $FE;
    If MouseWhat = 0 then Exit; { Только evMouseMove }
  end;
  Case MouseWhat of
    2:  MouseEvent.What := evLButtonDown;
    4:  MouseEvent.What := evLButtonUp;
    8:  MouseEvent.What := evRButtonDown;
    16: MouseEvent.What := evRButtonUp;
  end;
  RegisterNewEvent(MouseEvent);
End;

Procedure MouseKeeper; far; assembler;
Asm
        push  ax
        mov   ax,seg @Data
        mov   ds,ax
        pop   ax
        mov   MouseWhat,al
        mov   MouseEvent.Where.X,cx
        mov   MouseEvent.Where.Y,dx
        mov   MouseButtons,bl
        call  MouseProc
End;

Function ReadKeyWord:word; inline($B4/$10/$CD/$16);

Function KeyPressed:boolean; assembler;
Asm
        mov  ah,11h
        int  16h
        mov  al,0
        jz   @@End
        mov  al,1
@@End:
End;

Const SkipCnt:byte = 0; { Счетчик пропуска неиспользуемых скэн-кодов }
      WasE0:boolean = false;  { Признак префикса }
      LastKey:word = kbNoKey; { Отслеживание автоповтора }
      KeyCacheSize = 8;
      KeyCache:array[1..KeyCacheSize] of word = (0,0,0,0,0,0,0,0);
      Port60:byte = 0;

Procedure KeyboardProc;
Var NewEvent:TEvent; I,State:byte;
Begin
  If SkipCnt > 0 then begin
    Dec(SkipCnt);  Exit;
  end;
  Case Port60 of
    $E0: begin  WasE0 := true; Exit;  end;
    $AA,$2A: If WasE0 then begin  WasE0 := false; Exit;  end;
    $E1: begin  SkipCnt := 5; Exit;  end;
    $C5,$C6,$BA,$FA: Exit;  {NumLock, ScrollLock, CapsLock}
  end;
  WasE0 := false;
(*  Asm { Получение состояния регистров (Shift, Ctrl, Alt etc.) }
        mov  AH,02
        int  16h
        and  al,$7F
        mov  State,AL
  end;*)
  If Port60 and $80 = 0 then begin { Клавиша нажата }
    NewEvent.What := evKeyDown;
    If KeyPressed then begin
      NewEvent.KeyCode := ReadKeyWord;
      If (NewEvent.Symbol = #$E0) And (Port60 <> $23) then
        NewEvent.KeyCode := NewEvent.KeyCode and $FF00;
    end else begin
      NewEvent.Scan := Port60;
      NewEvent.Symbol := #0;
    end;
    NewEvent.Auto := (LastKey = NewEvent.KeyCode);
    If NewEvent.Auto then { Автоповтор }
      If Port60 in [29,42,54,56] then
        Exit; { Запрет автоповтора для регистров }
    LastKey := NewEvent.KeyCode;
    RegisterNewEvent(NewEvent);
    If NewEvent.Scan <> 0 then begin { Помещение в кэш }
      Move(KeyCache, KeyCache[2], SizeOf(KeyCache)-SizeOf(word));
      KeyCache[1] := NewEvent.KeyCode;
    end;
  end else begin { Клавиша отжата }
    NewEvent.What := evKeyUp;
    NewEvent.Scan := Port60 and $7F;
    NewEvent.Symbol := #0;
    NewEvent.Auto := false; { Автоповтора для KeyUp не бывает }
    For I := 1 to KeyCacheSize do { Поиск символа в кэше }
      If Hi(KeyCache[I]) = NewEvent.Scan then begin
        NewEvent.Symbol := Chr(Lo(KeyCache[I]));
        Break;
      end;
    RegisterNewEvent(NewEvent);
    LastKey := kbNoKey;
  end;
End;

Procedure KeyboardKeeper; far; assembler;
Asm
        cli
        pusha
        push  ds
        push  es
        mov   ax,seg @Data
        mov   ds,ax

        in    al,$60
        mov   Port60,al
        pushf
        call  dword ptr PrevKeyboardKeeper
        call  KeyboardProc
        pop   es
        pop   ds
        popa
        sti
        iret
End;

Procedure InitDriver;
Var I:byte;
Begin
  Asm { Проверка на наличие драйвера мыши }
  MOV AX,3533H
  INT 21H
  MOV AX,ES
  OR  AX,BX
  JE  @@1
  XOR AX,AX
  INT 33H
  OR  AX,AX
  JE  @@1
  PUSH  BX
  MOV AX,4
  XOR CX,CX
  XOR DX,DX
  INT 33H
  POP AX
@@1:  MOV ButtonCount,AL
  end;
  If ButtonCount = 0 then
    Exit; { Драйвера мыши нет }
  Asm { Установка обработчика мыши }
        mov  ax,$000C
        mov  cx,$001F { Принимаемые события: move, right & left buttons }
        mov  dx,seg MouseKeeper
        mov  es,dx
        mov  dx,offset MouseKeeper
        int  33h
  end;
  MouseEvents := true;
  ShowMouse;
 { Установка клавиатурного обработчика }
  Asm
        mov  ax,$0C0B
        int  $21      { Очистка клавиатурного буфера }
  end;
  GetIntVec($09, PrevKeyboardKeeper);
  SetIntVec($09, @KeyboardKeeper);
  KeyboardEvents := true;
 { Подготовка очереди событий - изначально очередь пуста }
  EventFirst := 1;  EventNext := 1;
 { Подготовка таймеров }
  For I := 1 to MaxTimers do Timers[I].Interval := 0;
End;

Procedure DoneDriver;
Begin
  If MouseEvents then begin
    HideMouse;
    Asm
          mov  ax,$000C
          mov  cx,$0000
          mov  dx,0
          mov  es,dx
          mov  dx,0
          int  33h
    end;
    MouseEvents := false;
  end;
  If KeyboardEvents then begin
    SetIntVec($09, PrevKeyboardKeeper);
    KeyboardEvents := false;
  end;
End;

Procedure GetNextEvent(var Event:TEvent);
Var NewEvent:TEvent; I:byte; Time,TimeLast:real; Now:boolean; Lost:integer;
Const TickInterval = 655360/1193181; { Интервал, сек/10, м/д двумя тиками }
Begin
 { Анализ списка таймеров }
  For I := 1 to MaxTimers do with Timers[I] do
    If Interval <> 0 then begin { Этот таймер работает }
      If LastTicks = Ticks then Continue;
      TimeLast := (Ticks - LastTicks) * TickInterval;
      Lost := Round(TimeLast / Interval) - 1; { Кол-во потеряных событий }
      If Lost < 0 then Continue;
      Time := (Ticks - StartTicks) * TickInterval; { Время от запуска таймера }
      Time := Time - Trunc(Time / Interval) * Interval;
      Now := (Abs(Time) < TickInterval);
      If (Lost = 0) And Not Now then Continue;
      LastTicks := Ticks;
      Event.What := evTimer;  Event.Timer := I;
      Event.Precision := Now;  Event.Lost := Lost;
      Exit; { Возвращаем событие таймера }
    end;
 { Выборка события из очереди }
  While EventFirst <> EventNext do begin { Ищем первое непустое событие }
    Event := EventQueue[EventFirst];
    Inc(EventFirst);
    If EventFirst > EventQueueSize then
      EventFirst := 1;
    If Event.What <> evNothing then { В очереди могут быть пустые события }
      Exit; { Событие найдено }
  end;
  Event.What := evNothing; { Ничего не произошло }
End;

Procedure ShowMouse; assembler;
Asm
  mov ax,$0001
  int 33h
End;

Procedure HideMouse; assembler;
Asm
  mov ax,$0002
  int 33h
End;

Procedure SetMousePos(X,Y:integer);
Begin
  Asm
    mov ax,$0004
    mov cx,X
    mov dx,Y
    int 33h
  end;
  MousePos.X := X;  MousePos.Y := Y;
End;

Function MakeTimer(Time:longint):byte;
Var I:byte;
Begin
  MakeTimer := 0;
  If Time <= 0 then Exit; { Некорректное значение Time }
  For I := 1 to MaxTimers do with Timers[I] do
    If Interval = 0 then begin { Найден неиспользованный таймер }
      MakeTimer := I;
     { Инициализация нового таймера }
      Interval := Time;  StartTicks := Ticks;  LastTicks := StartTicks;
      Break;
    end;
End;

Procedure KillTimer(Timer:byte);
Begin
  Timers[Timer].Interval := 0;
  {! Убрать из очереди все события этого таймера }
End;

Function Sign(X:integer):integer; { Знак числа X }
Begin
  If X > 0 then Sign := 1
           else If X < 0 then Sign := -1
                         else Sign := 0;
End;

Procedure PhantomTrackMouse(Target:TPoint);
Var TimerNo:byte; Event:TEvent; Start:TPoint; DX,DY:integer;
Begin
  TimerNo := MakeTimer(1);
  Start := MousePos;
  While (Target.X <> MousePos.X) Or (Target.Y <> MousePos.Y) do begin
    GetNextEvent(Event);
    If (Event.What = evTimer) And
       (Event.Timer = TimerNo) then begin
      DX := Target.X - MousePos.X;
      DY := Target.Y - MousePos.Y;
      If Abs(DX) >= 4 then DX := DX div 4 else DX := Sign(DX);
      If Abs(DY) >= 4 then DY := DY div 4 else DY := Sign(DY);
      SetMousePos(MousePos.X+DX, MousePos.Y+DY);
    end;
  end;
  KillTimer(TimerNo);
End;

End.
