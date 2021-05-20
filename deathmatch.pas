Program CityDeathmatch;

{ Change allegro.pas unit directory here: }
{$UNITPATH C:\allegro.pas-5.*\src\lib;~/allegro.pas-5.*/obj;../allegro.pas-5.*/obj}

Uses
  sysutils, math, al5base, al5strings, allegro5, al5font, al5image, al5primitives;

Type
  CarPtr = ^Car;
  
  Player = record
    up, down, left, right, armed, dead, driving: boolean;
    a, x, y: float;
    counter, tsd: integer;
    car: CarPtr;
  end;
  PlayerPtr = ^Player;
  
  Car = record
    counter: integer;
    a, x, y, xv, yv, acc: float;
    occupied, wrecked: boolean;
    driver: PlayerPtr;
  end;
  
  Bullet = record
    x, y, xv, yv: float;
    shooter: PlayerPtr;
  end;
  BulletPtr = ^Bullet;
  
  Map = record
    w, h: integer;
    map: array[0..65536] of byte;
  end;
  
  GameState = (GAME, EDITOR);

Const
  PI = 3.14159;

Var
  gTimer: ALLEGRO_TIMERptr;
  gQueue: ALLEGRO_EVENT_QUEUEptr;
  gDisp: ALLEGRO_DISPLAYptr;
  gFont: ALLEGRO_FONTptr;
  gTileset, gPlayerSheet, gMinimap, gCarSheet: ALLEGRO_BITMAPptr;
  gEvent: ALLEGRO_EVENT;

  gP1, gP2: Player;
  gMap: array[0..65536] of byte;
  gMapW, gMapH, gEX, gEY, gEXV, gEYV, gETile, gBulletNum, gESpeed, gWidth, gHeight, gCarNum: integer;
  gPlayers: array[1..2] of PlayerPtr;
  gBullets: array[1..35] of Bullet;
  gCars: array[1..35] of Car;
  gQuit, gRedraw, gEPlacing, gEResizing: boolean;
  gState: GameState;

Procedure EnsureInit(cond: boolean; desc: string);
Begin
  if cond then exit;
  writeln('failed to initialize ', desc);
  halt(1);
End;

Procedure InitAllegro;
Begin
  EnsureInit(al_init, 'allegro');
  EnsureInit(al_install_keyboard, 'keyboard');
  EnsureInit(al_init_image_addon, 'image addon');
  EnsureInit(al_init_primitives_addon, 'primitives');

  gTimer := al_create_timer(1 / 30);
  EnsureInit(gTimer <> nil, 'timer');
  gQueue := al_create_event_queue;
  EnsureInit(gQueue <> nil, 'event queue');
  gWidth := 640;
  gHeight := 400;
  al_set_new_display_flags(ALLEGRO_WINDOWED or ALLEGRO_RESIZABLE);
  gDisp := al_create_display(gWidth, gHeight);
  EnsureInit(gDisp <> nil, 'display');
  gFont := al_create_builtin_font;
  EnsureInit(gFont <> nil, 'font');

  al_register_event_source(gQueue, al_get_keyboard_event_source);
  al_register_event_source(gQueue, al_get_display_event_source(gDisp));
  al_register_event_source(gQueue, al_get_timer_event_source(gTimer));

  gTileset := al_load_bitmap('data/tileset.png');
  EnsureInit(gTileset <> nil, 'tileset');
  gPlayerSheet := al_load_bitmap('data/player.png');
  EnsureInit(gPlayerSheet <> nil, 'player spritesheet');
  gCarSheet := al_load_bitmap('data/car.png');
  EnsureInit(gCarSheet <> nil, 'car spritesheet');
End;

Procedure EndAllegro;
Begin
  al_destroy_bitmap(gCarSheet);
  al_destroy_bitmap(gPlayerSheet);
  al_destroy_bitmap(gTileset);

  al_destroy_font(gFont);
  al_destroy_display(gDisp);
  al_destroy_event_queue(gQueue);
  al_destroy_timer(gTimer);
End;

Procedure InitMinimap;
Var
  x, y, t: integer;
Begin
  if gMinimap <> nil then
    al_destroy_bitmap(gMinimap);
  gMinimap := al_create_bitmap(gMapW, gMapH);
  
  al_lock_bitmap(gMinimap, ALLEGRO_PIXEL_FORMAT_ANY, ALLEGRO_LOCK_WRITEONLY);
  al_set_target_bitmap(gMinimap);
  for x := 0 to gMapW-1 do
    for y := 0 to gMapH-1 do
    begin
      t := gMap[y*gMapW+x];
      if (t mod 2 <> 0) and (t <> 3) then
        al_put_pixel(x, y, al_map_rgb($ff, $ff, $ff))
      else if (t = 3) or (t = 8) then
        al_put_pixel(x, y, al_map_rgba($af, $af, $af, $af))
      else if t = 0 then
        al_put_pixel(x, y, al_map_rgba($e0, $e0, $e0, $e0))
      else
        al_put_pixel(x, y, al_map_rgba($44,$44,$44,$44));
    end;
  al_unlock_bitmap(gMinimap);
  al_set_target_backbuffer(gDisp);
End;

Procedure SpawnPlayer(p: PlayerPtr);
Var
  x, y: integer;
Begin
  p^.a := PI;
  p^.up := false;
  p^.down := false;
  p^.left := false;
  p^.right := false;
  p^.armed := false;
  p^.dead := false;
  p^.driving := false;
  p^.counter := 0;
  while true do
  begin
    x := random(gMapW);
    y := random(gMapH);
    if (gMap[y*gMapW+x] mod 2 = 0) and (gMap[y*gMapW+x] <> 2) then break;
  end;
  p^.x := x * 32;
  p^.y := y * 32;
End;

Procedure SaveMap;
Var
  m: Map;
  f: file of Map;
  x, y: integer;
Begin
  for x := 0 to gMapW-1 do
    for y := 0 to gMapH-1 do
      m.map[y*gMapW+x] := gMap[y*gMapW+x];
  m.w := gMapW;
  m.h := gMapH;
  
  assign(f, 'data/level1.bin');
  rewrite(f, sizeof(m));
  write(f, m);
  close(f);
End;

Procedure LoadMap;
Var
  m: map;
  f: file of Map;
  x, y: integer;
Begin
  assign(f, 'data/level1.bin');
  reset(f);
  read(f, m);
  close(f);
  
  gMapW := m.w;
  gMapH := m.h;
  for x := 0 to m.w-1 do
    for y := 0 to m.h-1 do
      gMap[y*m.w+x] := m.map[y*m.w+x];
End;

Procedure SpawnCar(c: CarPtr);
Var
  x, y, i: integer;
Begin
  while true do
  begin
    x := random(gMapW);
    y := random(gMapH);
    
    if gMap[y*gMapW+x] <> 8 then
      continue;
      
    i := 1;
    while i <= gCarNum do
    begin
      if (power(gCars[i].x-x*32, 2) + power(gCars[i].y-y*32, 2) < 320*320) and (@gCars[i] <> c) then
        break;
      i += 1;
    end;
    if i <= gCarNum then continue;
    
    i := 1;
    while i <= 2 do
    begin
      if power(gPlayers[i]^.x-x*32, 2) + power(gPlayers[i]^.y-y*32, 2) < 160*160 then
        break;
      i += 1;
    end;
    if i < 2 then continue;
    
    break;
  end;
    
  c^.x := x*32+16;
  c^.y := y*32+16;
  c^.yv := 0;
  c^.xv := 0;
  c^.acc := 0;
  c^.occupied := false;
  c^.wrecked := false;
  c^.counter := 0;
  c^.a := random(trunc(PI*2*10))/10;
End;

Procedure InitCars;
Var
  i: integer;
Begin
  gCarNum := 0;
  for i := 1 to 15 do
  begin
    SpawnCar(@gCars[i]);
    gCarNum := i;
  end;
End;

Procedure InitGame;
Begin
  gState := GAME;
  gMinimap := nil;
  randomize;
  InitMinimap;
  gBulletNum := 0;
  SpawnPlayer(@gP1);
  SpawnPlayer(@gP2);
  gPlayers[1] := @gP1;
  gPlayers[2] := @gP2;
  InitCars;
End;

Procedure EndGame;
Begin
  al_destroy_bitmap(gMinimap);
End;

Procedure InitEditor;
Begin
  gState := EDITOR;
  gEPlacing := false;
  gEResizing := false;
  gESpeed := 5;
  gEXV := 0;
  gEYV := 0;
  gETile := 2;
  gEX := 16;
  gEY := 16;
End;

Procedure EndEditor;
Begin
  gState := GAME;
  SpawnPlayer(@gP1);
  SpawnPlayer(@gP2);
  InitCars;
  gBulletNum := 0;
  InitMinimap;
End;

Function WithinTile(x, y: float; tx, ty: integer): boolean;
Begin
  WithinTile := ((x > tx*32) and (y > ty*32) and (x < tx*32+32) and (y < ty*32+32));
End;

Function TileAtXY(x, y: float): integer;
Var
  tx, ty, x1, y1, x2, y2: integer;
Begin
  x1 := trunc(x+16-32) shr 5;
  x2 := trunc(x+16+32) shr 5;
  y1 := trunc(y+16-32) shr 5;
  y2 := trunc(y+16+32) shr 5;
  if x1 < 0 then x1 := 0;
  if y1 < 0 then y1 := 0;
  if x2 >= gMapW then x2 := gMapW - 1;
  if y2 >= gMapH then y2 := gMapH - 1;
  for tx := x1 to x2 do
    for ty := y1 to y2 do
      if WithinTile(x, y, tx, ty) then
      begin
        TileAtXY := gMap[ty*gMapW+tx];
        exit;
      end;
End;

Procedure MovePlayer(p: PlayerPtr; xm, ym: float);
Var
  x, y, i: integer;
  dx, dy: float;
Begin
  dx := p^.x + xm;
  dy := p^.y + ym;
  
  for i := 1 to 2 do
    if (power(gPlayers[i]^.x-dx, 2) + power(gPlayers[i]^.y-dy, 2) < 16*16)
      and (gPlayers[i] <> p) and (not gPlayers[i]^.dead) then exit;

  if (dx+8<0) or (dy+8<0) or (dx+24>=gMapW*32) or (dy+24>=gMapH*32) then exit;
  for x := 0 to gMapW-1 do
    for y := 0 to gMapH-1 do
      if (gMap[y*gMapW+x] mod 2 <> 0)
        and ((WithinTile(dx+8,dy+8,x,y)) or (WithinTile(dx+24,dy+8,x,y))
          or (WithinTile(dx+8,dy+24,x,y)) or (WithinTile(dx+24,dy+24,x,y))) then exit;

  p^.x := dx;
  p^.y := dy;
End;

Procedure MovePlayerAndSlide(p: PlayerPtr; a, v: float);
Var
  am: integer;
Begin
  v /= 4;
  for am := 0 to 4 do
  begin
    MovePlayer(p, cos(a-(PI/8)*am)*v, sin(a-(PI/8)*am)*v);
    MovePlayer(p, cos(a+(PI/8)*am)*v, sin(a+(PI/8)*am)*v);
    v *= 0.9;
  end;
End;

Procedure PlayerShoot(p: PlayerPtr);
Var
  b: BulletPtr;
Begin
  p^.counter := 10;
  b := @gBullets[gBulletNum+1];
  b^.x := p^.x + cos(p^.a)*10+16;
  b^.y := p^.y + sin(p^.a)*10+16;
  b^.xv := cos(p^.a)*16;
  b^.yv := sin(p^.a)*16;
  b^.shooter := p;
  gBulletNum += 1;
End;

Procedure KillPlayer(p: PlayerPtr);
Begin
  p^.dead := true;
  p^.driving := false;
  p^.counter := 0;
  p^.tsd := 0;
End;

Procedure DeleteBullet(i: integer);
Var
  b: BulletPtr;
Begin
  gBulletNum -= 1;
  if gBulletNum = 0 then exit;
  b := @gBullets[gBulletNum+1];
  gBullets[i].x := b^.x;
  gBullets[i].y := b^.y;
  gBullets[i].xv := b^.xv;
  gBullets[i].yv := b^.yv;
End;

Procedure UpdateBullets;
Var
  i, j, k: integer;
  b: BulletPtr;
  p: PlayerPtr;
Begin
  for k := 1 to 8 do
  begin
    i := 1;
    while i < gBulletNum+1 do
    begin
      b := @gBullets[i];
      b^.x += b^.xv / 8;
      b^.y += b^.yv / 8;
      if (b^.x < 0) or (b^.y < 0) or (b^.x >= gMapW*32) or (b^.y >= gMapH*32) then
      begin
        DeleteBullet(i);
        continue;
      end
      else if TileAtXY(b^.x, b^.y) mod 2 > 0 then
      begin
        DeleteBullet(i);
        continue;
      end;
      for j := 1 to 2 do
      begin
        p := gPlayers[j];
        if (power(p^.x+16-b^.x, 2) + power(p^.y+16-b^.y, 2) < 16*16) and (not p^.dead)
          and (p <> b^.shooter) then
        begin
          KillPlayer(p);
          p^.a := ArcTan2(b^.yv, b^.xv);
          DeleteBullet(i);
          continue;
        end;
      end;
      i += 1;
    end;
  end;
End;

Procedure UpdatePlayer(p: PlayerPtr);
Var
  x, y: integer;
Begin
  if p^.dead then
  begin
    if p^.counter < 125 then p^.counter += 1;
    p^.tsd += 1;
    if p^.tsd > 200 then SpawnPlayer(p);
    exit;
  end;
  
  if p^.driving then
  begin
    p^.x := p^.car^.x-16;
    p^.y := p^.car^.y-16;
    exit;
  end;
  
  if p^.counter <> 0 then
    p^.counter -= 1;

  if p^.armed then
  begin
    if p^.left then p^.a -= 0.05;
    if p^.right then p^.a += 0.05;
    if p^.a < 0 then p^.a += PI*2;
    if p^.a > PI*2 then p^.a -= PI*2;
    if p^.up then MovePlayerAndSlide(p, p^.a, 2);
    if p^.down then MovePlayerAndSlide(p, p^.a-PI, 1.5);
  end
  else
  begin
    x := 0;
    y := 0;
    if p^.up then y := -1;
    if p^.down then y := 1;
    if p^.left then x := -1;
    if p^.right then x := 1;
    if (x <> 0) or (y <> 0) then
    begin
      MovePlayerAndSlide(p, p^.a, 3);
      p^.a := ArcTan2(y,x);
    end;
  end;
End;

Procedure WreckCar(c: CarPtr);
Begin
  if c^.occupied then
    KillPlayer(c^.driver);
  c^.wrecked := true;
  c^.occupied := false;
  c^.counter := 0;
End;

Procedure BounceCar(c: CarPtr; m: float);
Begin
  c^.x -= cos(c^.a)*m;
  c^.y -= sin(c^.a)*m;
  c^.xv *= -0.5;
  c^.yv *= -0.5;
  c^.acc := 0;
End;

Procedure CrashCar(c: CarPtr; m: float);
Begin
  if c^.xv*c^.xv + c^.yv*c^.yv > 32*32 then
    WreckCar(c)
  else
    BounceCar(c, m);
End;

Procedure MoveCar(c: CarPtr; x, y: float);
Var
  dx, dy: float;
  i: integer;
Begin
  dx := trunc(c^.x + x);
  dy := trunc(c^.y + y);
  
  if (dx-32 < 0) or (dy-32 < 0) or (dx+32 >= gMapW*32) or (dy+32 >= gMapH*32) then
  begin
    CrashCar(c, 3);
    exit;
  end;
  
  if (TileAtXY(dx+cos(c^.a)*64, dy+sin(c^.a)*64) mod 2 <> 0)
    or (TileAtXY(dx+cos(c^.a)*64-cos(c^.a+PI/2)*32, dy+sin(c^.a)*64-sin(c^.a+PI/2)*32) mod 2 <> 0)
    or (TileAtXY(dx+cos(c^.a)*64+cos(c^.a+PI/2)*32, dy+sin(c^.a)*64+sin(c^.a+PI/2)*32) mod 2 <> 0) then
  begin
    CrashCar(c, 3);
    exit;
  end;
  if (TileAtXY(dx-cos(c^.a)*64, dy-sin(c^.a)*64) mod 2 <> 0)
    or (TileAtXY(dx-cos(c^.a)*64-cos(c^.a+PI/2)*32, dy-sin(c^.a)*64-sin(c^.a+PI/2)*32) mod 2 <> 0)
    or (TileAtXY(dx-cos(c^.a)*64+cos(c^.a+PI/2)*32, dy-sin(c^.a)*64+sin(c^.a+PI/2)*32) mod 2 <> 0) then
  begin
    CrashCar(c, -3);
    exit;
  end;
  
  for i := 1 to gCarNum do
    if (@gCars[i] <> c) and (power(gCars[i].x-c^.x, 2) + power(gCars[i].y-c^.y, 2) < 64*64) then
    begin
      gCars[i].xv += c^.xv*2;
      gCars[i].yv += c^.yv*2;
      gCars[i].a += (random(3)-1)*0.1;
      c^.x -= c^.xv*2;
      c^.y -= c^.yv*2;
      BounceCar(c, -3);
      exit;
    end;
  
  c^.x := dx;
  c^.y := dy;
End;

Procedure UpdateCars;
Var
  i, j: integer;
  c: CarPtr;
Begin
  if gCarNum <= 0 then exit;
  for i := 0 to gCarNum-1 do
  begin
    c := @gCars[i];
    if c^.wrecked then
    begin
      c^.counter += 1;
      if c^.counter > 300 then SpawnCar(c);
      exit;
    end;
    
    if c^.counter > 0 then
      c^.counter -= 1;

    MoveCar(c, c^.xv, c^.yv);
    
    if c^.occupied then
    begin
      if (c^.driver^.up) and (c^.acc < 4) then c^.acc += 0.4;
      if (c^.driver^.down) and (c^.acc > -4) then c^.acc -= 0.2;
      if c^.driver^.left then c^.a -= 0.02*c^.acc;
      if c^.driver^.right then c^.a += 0.02*c^.acc;
      if c^.xv*c^.xv + c^.yv*c^.yv < 64*64 then
      begin
        c^.xv += cos(c^.a)*c^.acc;
        c^.yv += sin(c^.a)*c^.acc;
      end;
      if not c^.driver^.driving then
      begin
        c^.occupied := false;
        c^.counter := 100;
      end;
    end;
    
    c^.xv *= 0.8;
    c^.yv *= 0.8;
    if (c^.xv < 0.5) and (c^.xv > -0.5) then c^.xv := 0;
    if (c^.yv < 0.5) and (c^.yv > -0.5) then c^.yv := 0;
    
    if c^.acc > 0 then c^.acc -= 0.1;
    if c^.acc < 0 then c^.acc += 0.1;
    
    for j := 1 to 2 do
      if power(gPlayers[j]^.x-c^.x, 2) + power(gPlayers[j]^.y-c^.y, 2) < 32*32 then
      begin
        if (not c^.occupied) and (c^.counter = 0) and (not gPlayers[j]^.dead)
          and (not gPlayers[j]^.driving) and (c^.xv = 0) and (c^.yv = 0) then
        begin
          c^.occupied := true;
          c^.driver := gPlayers[j];
          gPlayers[j]^.driving := true;
          gPlayers[j]^.car := c;
        end
        else if (not gPlayers[j]^.driving) and (not gPlayers[j]^.dead) and (c^.xv*c^.xv + c^.yv*c^.yv > 2*2) then
        begin
          if c^.counter = 0 then
            KillPlayer(gPlayers[j])
          else if c^.driver <> gPlayers[j] then
		    KillPlayer(gPlayers[j]);
		end;
      end;
  end;
End;

Procedure UpdateEditor;
Var
  x, y, w, h: integer;
  mBuf: array[0..65536] of byte;
Begin
  if gEResizing then
  begin
    w := gMapW;
    h := gMapH;
    for x := 0 to w-1 do
      for y := 0 to h-1 do
        mBuf[y*gMapW+x] := gMap[y*gMapW+x];
    gMapW += gEXV;
    gMapH += gEYV;
    if gMapH*gMapW >= 255*255 then
    begin
      gMapW -= gEXV;
      gMapH -= gEYV;
    end;
    for x := 0 to gMapW do
      for y := 0 to gMapH do
        gMap[y*gMapW+x] := 2;
    for x := 0 to w-1 do
      for y := 0 to h-1 do
        gMap[y*gMapW+x] := mBuf[y*w+x];
    exit;
  end;
  
  gEX += gEXV * gESpeed;
  gEY += gEYV * gESpeed;
  if gEX < 0 then gEX := 0;
  if gEY < 0 then gEY := 0;
  if gEX > gMapW*32 then gEX := gMapW*32;
  if gEY > gMapH*32 then gEY := gMapH*32;
  
  if not gEPlacing then exit;
  gMap[(gEY div 32)*gMapW+(gEX div 32)] := gETile;
End;

Procedure Update;
Begin
  if gState = EDITOR then
  begin
    UpdateEditor;
    exit;
  end;
  UpdatePlayer(@gP1);
  UpdatePlayer(@gP2);
  UpdateBullets;
  UpdateCars;
  gRedraw := true;
End;

Procedure ControlGame;
Var
  keydown: boolean;
Begin
  keydown := false;
  if gEvent.ftype = ALLEGRO_EVENT_KEY_DOWN then keydown := true;

  if not gP1.dead then
    case gEvent.keyboard.keycode of
      ALLEGRO_KEY_W: gP1.up := keydown;
      ALLEGRO_KEY_S: gP1.down := keydown;
      ALLEGRO_KEY_A: gP1.left := keydown;
      ALLEGRO_KEY_D: gP1.right := keydown;
      ALLEGRO_KEY_1:
        if keydown then
        begin
          if gP1.driving then
            gP1.driving := false
          else
            gP1.armed := (not gP1.armed);
        end;
      ALLEGRO_KEY_2: if (gP1.counter = 0) and (gP1.armed) and (not gP1.driving) then PlayerShoot(@gP1);
    end;
    
  if not gP2.dead then
    case gEvent.keyboard.keycode of
      ALLEGRO_KEY_UP: gP2.up := keydown;
      ALLEGRO_KEY_DOWN: gP2.down := keydown;
      ALLEGRO_KEY_LEFT: gP2.left := keydown;
      ALLEGRO_KEY_RIGHT: gP2.right := keydown;
      ALLEGRO_KEY_COMMA:
        if keydown then
        begin
          if gP2.driving then
            gP2.driving := false
          else
            gP2.armed := (not gP2.armed);
        end;
      ALLEGRO_KEY_FULLSTOP: if (gP2.counter = 0) and (gP2.armed) and (not gP2.driving) then PlayerShoot(@gP2);
    end;
  
  case gEvent.keyboard.keycode of
    ALLEGRO_KEY_ESCAPE: gQuit := true;
    ALLEGRO_KEY_EQUALS: InitEditor;
  end;
End;

Procedure ControlEditor;
Begin
  if gEvent.ftype = ALLEGRO_EVENT_KEY_DOWN then
    case gEvent.keyboard.keycode of
      ALLEGRO_KEY_UP: gEYV := -1;
      ALLEGRO_KEY_DOWN: gEYV := 1;
      ALLEGRO_KEY_LEFT: gEXV := -1;
      ALLEGRO_KEY_RIGHT: gEXV := 1;
      ALLEGRO_KEY_ENTER, ALLEGRO_KEY_SPACE: if not gEResizing then gEPlacing := true;
      ALLEGRO_KEY_LCTRL, ALLEGRO_KEY_RCTRL: if not gEPlacing then gEResizing := true;
      ALLEGRO_KEY_LSHIFT, ALLEGRO_KEY_RSHIFT: gESpeed := 20;
    end
  else
    case gEvent.keyboard.keycode of
      ALLEGRO_KEY_UP, ALLEGRO_KEY_DOWN: gEYV := 0;
      ALLEGRO_KEY_LEFT, ALLEGRO_KEY_RIGHT: gEXV := 0;
      ALLEGRO_KEY_ENTER, ALLEGRO_KEY_SPACE: gEPlacing := false;
      ALLEGRO_KEY_LCTRL, ALLEGRO_KEY_RCTRL: gEResizing := false;
      ALLEGRO_KEY_LSHIFT, ALLEGRO_KEY_RSHIFT: gESpeed := 5;
      ALLEGRO_KEY_ESCAPE: gQuit := true;
      ALLEGRO_KEY_W: SaveMap;
      ALLEGRO_KEY_Q: EndEditor;
      ALLEGRO_KEY_PGUP: if gETile > 0 then gETile -= 1;
      ALLEGRO_KEY_PGDN: if gETile < 9 then gETile += 1;
    end;
End;

Procedure Control;
Begin
  if gState = GAME then ControlGame;
  if gState = EDITOR then ControlEditor;
End;

Procedure DrawMap(x1, y1, w, h, xo, yo, mode: integer);
Var
  x, y, x2, y2, t: integer;
Begin
  x2 := x1 + w + 1;
  y2 := y1 + h + 1;
  for x := x1 to x2 do
    for y := y1 to y2 do
    begin
      if (x < 0) or (y < 0) or (x >= gMapW) or (y >= gMapH) then
        continue;
      t := gMap[y*gMapW+x];
      if (mode = 0) and (t mod 2 <> 0) and (t <> 3) then continue;
      if (mode = 1) and ((t mod 2 = 0) or (t = 3)) then continue;
      al_draw_bitmap_region(gTileset, (t shr 1) shl 5, (t mod 2) * 32, 32, 32,
        x shl 5 + xo, y shl 5 + yo, 0);
    end;
End;

Procedure DrawPlayer(p: Player; sx, sy: float);
Var
  x, y, k: integer;
  s: float;
Begin
  if p.dead then
  begin
    s := p.counter / 100;
    al_draw_tinted_scaled_rotated_bitmap_region(gPlayerSheet, 96, 0, 32, 32,
      al_map_rgb($ff,$ff,$ff), 16, 16, trunc(sx+16), trunc(sy+16), s, s, PI/2, 0);
    al_draw_tinted_scaled_rotated_bitmap_region(gPlayerSheet, 64, 0, 32, 32,
      al_map_rgb($ff,$ff,$ff), 16, 16, trunc(sx+16), trunc(sy+16), 1, 1, p.a-PI/2, 0);
      exit;
  end;
  
  if p.driving then exit;

  k := p.counter div 2;
  if k <= 3 then k := k div 2;
  x := trunc(sx-cos(p.a)*k)+16;
  y := trunc(sy-sin(p.a)*k)+16;
  al_draw_tinted_scaled_rotated_bitmap_region(gPlayerSheet, 0, 0, 32, 32,
    al_map_rgb($ff,$ff,$ff), 16, 16, x, y, 1, 1, p.a+PI/2, 0);
  if p.armed then
    al_draw_tinted_scaled_rotated_bitmap_region(gPlayerSheet, 32, 0, 32, 32,
      al_map_rgb($ff,$ff,$ff), 16, 16, x, y, 1, 1, p.a+PI/2, 0);
End;

Procedure DrawMinimap(x, y: integer);
Begin
  al_draw_scaled_bitmap(gMinimap, 0, 0, gMapW, gMapH, x, y, gMapW*2, gMapH*2, 0);
  al_draw_filled_rectangle(x+trunc(gP1.x) shr 4 + 1, y+trunc(gP1.y) shr 4 + 1,
    x+trunc(gP1.x) shr 4 + 3, y+trunc(gP1.y) shr 4 + 3, al_map_rgb($ff,$00,$00));
  al_draw_filled_rectangle(x+trunc(gP2.x) shr 4 + 1, y+trunc(gP2.y) shr 4 + 1,
    x+trunc(gP2.x) shr 4 + 3, y+trunc(gP2.y) shr 4 + 3, al_map_rgb($00,$00,$ff));
End;

Procedure DrawBullets(xo, yo: integer);
Var
  i: integer;
  b: BulletPtr;
Begin
  i := 1;
  while i < gBulletNum+1 do
  begin
    b := @gBullets[i];
    al_draw_line(trunc(b^.x)+xo, trunc(b^.y)+yo, trunc(b^.x-b^.xv)+xo, trunc(b^.y-b^.yv)+yo,
      al_map_rgb($ff,$ff,$00), 1);
    i += 1;
  end;
End;

Procedure DrawCars(xo, yo: integer);
Var
  i: integer;
  c: CarPtr;
Begin
  if gCarNum < 1 then exit;
  for i := 1 to gCarNum do
  begin
    c := @gCars[i];
    if c^.wrecked then
    begin
      al_draw_tinted_scaled_rotated_bitmap_region(gCarSheet, 64, 0, 64, 128, al_map_rgb($ff,$ff,$ff),
        32, 64, c^.x+xo, c^.y+yo, 1, 1, c^.a+PI/2, 0);
    end
    else
      al_draw_tinted_scaled_rotated_bitmap_region(gCarSheet, 0, 0, 64, 128, al_map_rgb($ff,$ff,$ff),
        32, 64, c^.x+xo, c^.y+yo, 1, 1, c^.a+PI/2, 0);
  end;
End;

Procedure DrawScreen(p: Player; x, y, w, h: integer);
Var
  i: integer;
Begin
  al_set_clipping_rectangle(x, y, w, h);
  DrawMap(trunc(p.x-w/2) div 32, trunc(p.y-h/2) div 32, w div 32, h div 32, x+(w div 2)-trunc(p.x), y+(h div 2)-trunc(p.y), 0);
  for i := 1 to 2 do
    if gPlayers[i]^.dead then
      DrawPlayer(gPlayers[i]^, x+(w div 2)+gPlayers[i]^.x-p.x, y+(h div 2)+gPlayers[i]^.y-p.y);
  DrawBullets(trunc(x+(w div 2)-p.x), trunc(y+(h div 2)-p.y));
  DrawMap(trunc(p.x-w/2) div 32, trunc(p.y-h/2) div 32, w div 32, h div 32, x+(w div 2)-trunc(p.x), y+(h div 2)-trunc(p.y), 1);
  for i := 1 to 2 do
    if (not gPlayers[i]^.dead) then
      DrawPlayer(gPlayers[i]^, x+(w div 2)+gPlayers[i]^.x-p.x, y+(h div 2)+gPlayers[i]^.y-p.y);
  DrawCars(w div 2 - trunc(p.x) + x, h div 2 - trunc(p.y) + y);
  al_set_clipping_rectangle(0, 0, gWidth, gHeight);
End;

Procedure DrawGame;
Begin
  DrawScreen(gP1, 0, 0, gWidth div 2, gHeight);
  DrawScreen(gP2, gWidth div 2, 0, gWidth div 2, gHeight);
  DrawMiniMap(gWidth div 2 - gMapW, 0);
End;

Procedure DrawEditorUI;
Var
  stats: string;
Begin
  al_draw_line(gWidth div 2 - 3, gHeight div 2 - 3, gWidth div 2 + 3, gHeight div 2 + 3, al_map_rgb($ff,$ff,$ff), 1);
  al_draw_line(gWidth div 2 - 3, gHeight div 2 + 3, gWidth div 2 + 3, gHeight div 2 - 3, al_map_rgb($ff,$ff,$ff), 1);
  stats := 'x:' + IntToStr(gEX shr 5) + ' y:' + IntToStr(gEY shr 5);
  al_draw_text(gFont, al_map_rgb($ff,$ff,$ff), 0, 0, 0, stats);
  al_draw_bitmap(gTileset, gWidth-128-32, 0, 0);
  al_draw_rectangle(gWidth-128-32+32*(gETile div 2), 32*(gETile mod 2), gWidth-128-32+32+32*(gETile div 2), 32+32*(gETile mod 2), al_map_rgb($ff,$ff,$ff), 2);
  if gEResizing then
  begin
    stats := 'w:' + IntToStr(gMapW) + ' h:' + IntToStr(gMapH);
    al_draw_text(gFont, al_map_rgb($ff,$ff,$ff), gWidth div 2 - 20, gHeight div 2 - 20, 24, stats);
  end;
  al_draw_text(gFont, al_map_rgb($ff,$ff,$ff), 0, gHeight-16, 0, 'q: back to game  w: save map  enter: place tile  pgup/pgdn: select tile');
  al_draw_text(gFont, al_map_rgb($ff,$ff,$ff), 0, gHeight-8, 0, 'ctrl: resize map');
End;

Procedure DrawEditor;
Begin
  DrawMap((gEX - gWidth div 2) div 32, (gEY - gHeight div 2) div 32, gWidth div 32, gHeight div 32,
    gWidth div 2 - gEX, gHeight div 2 - gEY, 2);
  DrawEditorUI;
End;

Procedure Draw;
Begin
  al_clear_to_color(al_map_rgb($44,$54,$88));
  if gState = GAME then DrawGame;
  if gState = EDITOR then DrawEditor;
  al_flip_display;
End;

Procedure ResizeWindow;
Begin
  al_acknowledge_resize(gDisp);
  gWidth := al_get_display_width(gDisp);
  gHeight := al_get_display_height(gDisp);
End;

Begin
  InitAllegro;
  LoadMap;
  InitGame;

  gQuit := false;
  gRedraw := false;

  al_start_timer(gTimer);

  while not gQuit do
  begin
    al_wait_for_event(gQueue, @gEvent);
    case gEvent.ftype of
      ALLEGRO_EVENT_TIMER: Update;
      ALLEGRO_EVENT_DISPLAY_CLOSE: gQuit := true;
      ALLEGRO_EVENT_KEY_DOWN, ALLEGRO_EVENT_KEY_UP: Control;
      ALLEGRO_EVENT_DISPLAY_RESIZE: ResizeWindow;
    end;

    if (gRedraw) and (al_is_event_queue_empty(gQueue)) then
      Draw;
  end;

  EndGame;
  EndAllegro;
End.
