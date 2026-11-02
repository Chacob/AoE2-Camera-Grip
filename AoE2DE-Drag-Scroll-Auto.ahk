; =============================================================================
;  AoE2DE Drag Scroll - self-locating edition  (AutoHotkey v1.1, 64-bit)
;
;  Hold the pan key and drag to grip-pan the camera.
;  After a game update: start a match, centre the camera somewhere mid-map,
;  put the cursor over the map, press Ctrl+Alt+F. The script finds the new
;  offsets itself (~2-5 s, the camera nudges and zooms; first run after a big patch can take a minute or two)
;  and caches them per game build in AoE2DE-Drag-Scroll.ini.
;
;  Ctrl+Alt+F  re-locate offsets   Ctrl+Alt+D  diagnostics   Ctrl+Alt+R  reload
;
;  Offsets for builds someone has already located ship in known-builds.ini.
;
;  Run as administrator. Based on Emerald3ME/AoE2DE-Drag-Scroll (MIT),
;  itself a fork of asieradzk/AoE2Mouse_Camera_Drag (MIT).
; =============================================================================

#NoEnv
#SingleInstance Force
SetWorkingDir %A_ScriptDir%
SetBatchLines, -1
Process, Priority,, High
DllCall("winmm.dll\timeBeginPeriod", "UInt", 1)

if (A_PtrSize != 8) {
    MsgBox, 16, AoE2DE Drag Scroll, This script needs 64-bit AutoHotkey (AoE2DE is a 64-bit game).
    ExitApp
}

PanKey := "MButton"   ; e.g. "RButton", "XButton1", "XButton2"

; ---- Pointer-chain shape:  [module + Base] -> +Hop -> camera struct ; X at +XOff, Y at +XOff+4 ----
; Defaults = the last layout known to work (Nov 2026). Ctrl+Alt+F also searches Hop/XOff within
; the ranges below, because patches have changed the struct layout before (X/Y moved 0x2F0 -> 0x228).
global PtrHop := 0x28, CamXOff := 0x228, MaxMapCoord := 520.0
global HopMin := 0x08, HopMax := 0x60, XOffMin := 0x200, XOffMax := 0x3F8

; ---- Where to start searching (last offsets known to work; updated automatically) ----
global HintBase := 0x435BD70, HintZoom := 0x3DAAF94

; ---- Feel (same defaults as the original) ----
BasePanSpeed         := 0.0341
InvertX              := 1
InvertY              := 1
SmoothingSlow        := 0.5
BaseZoom             := 1.0
HorizontalMultiplier := 0.42
VerticalMultiplier   := 0.86
DeadZonePixels       := 1.5
DragThreshold        := 12    ; px of travel before it counts as a drag
ClickTimeThreshold   := 180   ; ms held before it counts as a drag

global GameExe := "AoE2DE_s.exe"
global IniFile := A_ScriptDir "\AoE2DE-Drag-Scroll.ini"        ; your local cache (not committed)
global KnownFile := A_ScriptDir "\known-builds.ini"            ; shipped offsets for builds others have located
global g_h := 0, g_Pid := 0, g_ModBase := 0, g_Build := "", g_Secs := ""
global g_Base := 0, g_Zoom := 0, g_LastScan := "", g_Hop := 0x28, g_XOff := 0x2F0

IniRead, t, %IniFile%, General, LastBase, %A_Space%
if (t != "")
    HintBase := t + 0
IniRead, t, %IniFile%, General, LastZoom, %A_Space%
if (t != "")
    HintZoom := t + 0

Hotkey, IfWinActive, ahk_exe %GameExe%
Hotkey, $%PanKey%, StartPan
Hotkey, ^!f, LocateOffsets
Hotkey, ^!d, Diagnose
Hotkey, IfWinActive
return

^!r::Reload

; =============================================================================
;  Panning
; =============================================================================
StartPan:
    DidDrag     := false
    TotalTravel := 0
    PressTime   := A_TickCount

    camBase := 0
    if (EnsureGame())
        camBase := ResolveCam(g_ModBase + g_Base)
    if (!camBase) {                       ; not in a match / offsets unknown: behave like a normal click
        DetachGame()
        KeyWait, %PanKey%
        SendInput {%PanKey%}
        return
    }

    cameraXAddr := camBase + g_XOff
    cameraYAddr := cameraXAddr + 4
    zoomAddr    := g_Zoom ? g_ModBase + g_Zoom : 0

    DllCall("QueryPerformanceFrequency", "Int64*", perfFreq)
    DllCall("QueryPerformanceCounter", "Int64*", lastTime)
    MouseGetPos, lastX, lastY
    velX := 0, velY := 0, writeWarned := false
    lastGoodZoom := BaseZoom

    While GetKeyState(PanKey, "P")
    {
        if (!DidDrag && (A_TickCount - PressTime >= ClickTimeThreshold || TotalTravel >= DragThreshold))
            DidDrag := true

        DllCall("QueryPerformanceCounter", "Int64*", now)
        deltaTime := (now - lastTime) / perfFreq * 1000
        deltaTime := deltaTime < 1 ? 1 : deltaTime > 50 ? 50 : deltaTime
        timeMultiplier := deltaTime / 16.0
        lastTime := now

        currentZoom := zoomAddr ? ReadFloat(zoomAddr) : BaseZoom
        if (currentZoom < 0.1 || currentZoom > 5.0)
            currentZoom := lastGoodZoom
        else
            lastGoodZoom := currentZoom
        PanSpeed := BasePanSpeed * (BaseZoom / currentZoom)

        MouseGetPos, currentX, currentY
        rawDeltaX := currentX - lastX
        rawDeltaY := currentY - lastY
        TotalTravel += Abs(rawDeltaX) + Abs(rawDeltaY)

        if (Abs(rawDeltaX) < DeadZonePixels)
            rawDeltaX := 0
        if (Abs(rawDeltaY) < DeadZonePixels)
            rawDeltaY := 0
        if (rawDeltaX = 0 && rawDeltaY = 0) {
            Sleep, 3
            continue
        }
        lastX := currentX, lastY := currentY

        screenDeltaX := rawDeltaX * PanSpeed * timeMultiplier * HorizontalMultiplier
        screenDeltaY := rawDeltaY * PanSpeed * timeMultiplier * VerticalMultiplier

        ; rotate screen coords into AoE2's isometric space
        isoDeltaX := (screenDeltaX - screenDeltaY) * 0.707
        isoDeltaY := (screenDeltaX + screenDeltaY) * 0.707
        if (InvertX)
            isoDeltaX := -isoDeltaX
        if (InvertY)
            isoDeltaY := -isoDeltaY

        velX := velX * (1 - SmoothingSlow) + isoDeltaX * SmoothingSlow
        velY := velY * (1 - SmoothingSlow) + isoDeltaY * SmoothingSlow

        if (!WriteFloat(cameraXAddr, ReadFloat(cameraXAddr) + velX) && !writeWarned) {
            writeWarned := true
            Tip("Camera write failed (error " A_LastError "). Is the script running as administrator?", 6000)
        }
        WriteFloat(cameraYAddr, ReadFloat(cameraYAddr) + velY)
        Sleep, 3
    }

    DetachGame()
    if (!DidDrag)
        SendInput {%PanKey%}
return

; =============================================================================
;  Attaching to the game
; =============================================================================
AttachGame() {
    Process, Exist, %GameExe%
    pid := ErrorLevel
    if (!pid)
        return false
    if (pid = g_Pid && g_h)
        return true
    if (g_h)
        DllCall("CloseHandle", "Ptr", g_h)
    ; VM_READ | VM_WRITE | VM_OPERATION | QUERY_INFORMATION (no PROCESS_ALL_ACCESS)
    g_h := DllCall("OpenProcess", "UInt", 0x0438, "Int", false, "UInt", pid, "Ptr")
    if (!g_h) {
        g_Pid := 0
        Tip("Couldn't open " GameExe " - run this script as administrator.")
        return false
    }
    g_Pid := pid
    VarSetCapacity(mods, 8 * 1024, 0)
    if !DllCall("Psapi.dll\EnumProcessModulesEx", "Ptr", g_h, "Ptr", &mods, "UInt", 8 * 1024, "UInt*", need, "UInt", 0x03) {
        g_Pid := 0
        return false
    }
    g_ModBase := NumGet(mods, 0, "Ptr")      ; first module = the exe; HMODULE == base address
    ReadPE()
    src := IniFile
    IniRead, b, %src%, %g_Build%, Base, 0
    if (!(b + 0)) {
        src := KnownFile
        IniRead, b, %src%, %g_Build%, Base, 0
    }
    IniRead, z, %src%, %g_Build%, Zoom, 0
    IniRead, hp, %src%, %g_Build%, Hop, %PtrHop%
    IniRead, xo, %src%, %g_Build%, XOff, %CamXOff%
    g_Base := b + 0, g_Zoom := z + 0, g_Hop := hp + 0, g_XOff := xo + 0
    return true
}

; The game handle is only held while panning / locating / diagnosing, then closed again,
; so no other process sits on write access to the game the rest of the time.
DetachGame() {
    if (g_h)
        DllCall("CloseHandle", "Ptr", g_h)
    g_h := 0, g_Pid := 0
}

EnsureGame() {
    if (!AttachGame())
        return false
    if (!g_Base) {
        Tip("No camera offsets for this AoE2 build (" g_Build ") yet.`nIn a match: camera mid-map, cursor over the map, then press Ctrl+Alt+F.", 7000)
        return false
    }
    return true
}

; Reads the exe's PE header: build id (timestamp + image size) and writable data sections.
ReadPE() {
    g_Build := "unknown", g_Secs := []
    if !ReadBlockLoose(g_ModBase, hdr, 0x1000)
        return
    lfanew := NumGet(hdr, 0x3C, "Int")
    if (lfanew <= 0 || lfanew > 0xE00)
        return
    ts      := NumGet(hdr, lfanew + 8, "UInt")
    optSize := NumGet(hdr, lfanew + 20, "UShort")
    soi     := NumGet(hdr, lfanew + 24 + 56, "UInt")   ; OptionalHeader64.SizeOfImage
    g_Build := Format("build_{:08X}_{:X}", ts, soi)
    nSec := NumGet(hdr, lfanew + 6, "UShort")
    tab  := lfanew + 24 + optSize
    Loop % nSec {
        s := tab + (A_Index - 1) * 40
        if (s + 40 > 0x1000)
            break
        vsz := NumGet(hdr, s + 8, "UInt"), va := NumGet(hdr, s + 12, "UInt"), ch := NumGet(hdr, s + 36, "UInt")
        if ((ch & 0x80000000) && !(ch & 0x20000000) && vsz)    ; MEM_WRITE and not MEM_EXECUTE
            g_Secs.Push([va, va + vsz])
    }
}

; =============================================================================
;  Auto-locate (Ctrl+Alt+F)
; =============================================================================
LocateOffsets:
    if (AttachGame())
        Locate()
    DetachGame()
return

Locate() {
    KeyWait, Control
    KeyWait, Alt
    Sleep, 150
    if (!g_Secs.Length()) {
        Tip("Couldn't read the game's section table.", 6000)
        return
    }

    Tip("Locating camera - hands off (camera nudges right, then left)...", 0)
    found := FindCamera(Clip(g_Secs, HintBase - 0x20000, HintBase + 0x20000))
    if (!IsObject(found)) {
        Tip("Not near the previous offset - scanning all game data (can take a minute)...", 0)
        found := FindCamera(g_Secs, true)
    }
    if (!IsObject(found)) {
        Tip("Camera not found (" g_LastScan ").`nBe in a match, keep the camera away from map edges, and make sure the arrow keys still scroll.", 12000)
        return
    }
    base := found.off, g_Hop := found.hop, g_XOff := found.xo
    camInfo := g_LastScan " hop=" Hex(g_Hop) " xoff=" Hex(g_XOff)
    IniWrite, % Hex(g_Hop), %IniFile%, %g_Build%, Hop
    IniWrite, % Hex(g_XOff), %IniFile%, %g_Build%, XOff

    Tip("Locating zoom - hands off (zooms in, then back out)...", 0)
    WinGetPos, wx, wy, ww, wh, ahk_exe %GameExe%
    MouseMove, wx + ww // 2, wy + wh // 2, 0
    zoom := FindZoom(Clip(g_Secs, HintZoom - 0x40000, HintZoom + 0x40000))
    if (!zoom)
        zoom := FindZoom(g_Secs)

    IniWrite, % Hex(base), %IniFile%, %g_Build%, Base
    IniWrite, % Hex(zoom), %IniFile%, %g_Build%, Zoom
    IniWrite, % Hex(base), %IniFile%, General, LastBase
    g_Base := base, HintBase := base, g_Zoom := zoom
    if (zoom) {
        IniWrite, % Hex(zoom), %IniFile%, General, LastZoom
        HintZoom := zoom
        Tip("Ready. base = " Hex(base) ", zoom = " Hex(zoom) "`n" camInfo, 9000)
    } else
        Tip("Ready. base = " Hex(base) "`n" camInfo "`nZoom not found (don't start at max zoom-in) - pan speed won't follow zoom until you re-run Ctrl+Alt+F.", 12000)
    IniWrite, %camInfo%, %IniFile%, %g_Build%, LastScan
}

; Ctrl+Alt+D: show what the script sees right now (for troubleshooting)
Diagnose:
    info := "AHK " A_AhkVersion (A_IsAdmin ? " admin" : " NOT admin")
    if (!AttachGame()) {
        Tip(info "`nCan't attach to " GameExe, 10000)
        DetachGame()
        return
    }
    info .= "`nbuild " g_Build "  module " Hex(g_ModBase) "`nbase " Hex(g_Base) "  hop " Hex(g_Hop) "  xoff " Hex(g_XOff) "  zoom " Hex(g_Zoom)
    cam := g_Base ? ResolveCam(g_ModBase + g_Base) : 0
    if (cam && ReadXY(cam + g_XOff, dx, dy)) {
        info .= "`ncamera struct " Hex(cam) "  X=" Round(dx, 2) " Y=" Round(dy, 2)
        VarSetCapacity(wb, 4, 0), NumPut(dx, wb, 0, "Float")
        w := DllCall("WriteProcessMemory", "Ptr", g_h, "Ptr", cam + g_XOff, "Ptr", &wb, "UPtr", 4, "Ptr", 0)
        info .= "`nwrite test: " (w ? "ok" : "FAILED, error " A_LastError)
    } else
        info .= "`ncamera chain doesn't resolve (in a match?)"
    if (g_Zoom)
        info .= "`nzoom value " Round(ReadFloat(g_ModBase + g_Zoom), 3)
    IniRead, ls, %IniFile%, %g_Build%, LastScan, %A_Space%
    if (ls != "")
        info .= "`nlast locate: " ls
    Tip(info, 15000)
    DetachGame()
return


; Find the camera without assuming the struct layout:
;   for every pointer in the exe's static data, follow it, try each hop in [HopMin, HopMax],
;   and inside each struct look for an (X, Y) float pair in [XOffMin, XOffMax] with mid-map values.
; Then keep the pairs that follow arrow-key movement, and write-test them to find the one
; that actually drives the view. Returns {off, hop, xo} or 0.
FindCamera(ranges, allowUnconfirmed := false) {
    seen := {}, visited := {}, cands := []
    hopBytes := HopMax - HopMin + 8, xBytes := XOffMax - XOffMin + 8
    for i, r in ranges {
        size := r[2] - r[1]
        if (size < 8 || !ReadBlockLoose(g_ModBase + r[1], buf, size))
            continue
        off := 0
        while (off <= size - 8) {
            v := NumGet(buf, off, "Int64")
            if (v >= 0x10000 && v <= 0x7FFFFFFEFFFF && !(v & 7) && ReadRaw(v + HopMin, ab, hopBytes)) {
                h := 0
                while (h < hopBytes) {
                    c := NumGet(ab, h, "Int64")
                    if (c >= 0x10000 && c <= 0x7FFFFFFEFFFF && !(c & 7) && !visited.HasKey(c) && ReadRaw(c + XOffMin, cb, xBytes)) {
                        visited[c] := 1
                        xo := 0
                        while (xo <= xBytes - 8) {
                            x := NumGet(cb, xo, "Float"), y := NumGet(cb, xo + 4, "Float")
                            ; mid-map camera coords: in range and not whole numbers (filters sizes, counts, 1.0, 100.0 ...)
                            if (x > 2 && x < MaxMapCoord && y > 2 && y < MaxMapCoord && x != Floor(x) && y != Floor(y)) {
                                xa := c + XOffMin + xo
                                hop := HopMin + h, xof := XOffMin + xo
                                score := (Abs(hop - PtrHop) * 4 + Abs(xof - CamXOff)) * 0x10000 + Abs(r[1] + off - HintBase) // 16
                                if (!seen.HasKey(xa)) {
                                    seen[xa] := cands.Length() + 1
                                    cands.Push({off: r[1] + off, hop: hop, xo: xof, xa: xa, score: score})
                                } else if (score < cands[seen[xa]].score) {
                                    cands[seen[xa]] := {off: r[1] + off, hop: hop, xo: xof, xa: xa, score: score}
                                }
                            }
                            xo += 4
                        }
                    }
                    h += 8
                }
            }
            off += 8
        }
    }
    g_LastScan := "pairs=" cands.Length()
    if (!cands.Length())
        return 0

    s0 := SnapPairs(cands)
    HoldKey("Right", 600)
    s1 := SnapPairs(cands)
    HoldKey("Left", 600)
    s2 := SnapPairs(cands)

    movers := []
    for i, cd in cands {
        a := s0[i], b := s1[i], c := s2[i]
        if (!IsObject(a) || !IsObject(b) || !IsObject(c))
            continue
        dx1 := b[1] - a[1], dy1 := b[2] - a[2], dx2 := c[1] - b[1], dy2 := c[2] - b[2]
        m1 := Abs(dx1) + Abs(dy1), m2 := Abs(dx2) + Abs(dy2)
        if (m1 < 0.3 || m2 < 0.3 || m1 > 60 || m2 > 60)
            continue
        if (dx1 * dx2 + dy1 * dy2 >= 0)          ; must move, then move back
            continue
        pos := movers.Length() + 1
        for j, m in movers
            if (cd.score < m.score) {
                pos := j
                break
            }
        movers.InsertAt(pos, cd)
    }
    g_LastScan .= " moving=" movers.Length()
    if (!movers.Length())
        return 0
    return WriteTest(movers, allowUnconfirmed)
}

; The game keeps several copies of the camera position; only one actually drives the view.
; Nudge each candidate by +3 tiles: the real one keeps the value (and the copies follow it);
; a copy gets overwritten back by the game. Then restore the original position.
WriteTest(movers, allowUnconfirmed) {
    tested := 0, persistOnly := 0, persistIdx := 0
    for i, s in movers {
        if (i > 20)
            break
        tested++
        before := []
        for j, t in movers
            before[j] := ReadXY(t.xa, x, y) ? [x, y] : 0
        if (!IsObject(before[i]))
            continue
        x0 := before[i][1], y0 := before[i][2]
        WriteFloat(s.xa, x0 + 3)
        WriteFloat(s.xa + 4, y0 + 3)
        Sleep, 300
        ok := ReadXY(s.xa, x, y) && Abs(x - (x0 + 3)) < 0.5 && Abs(y - (y0 + 3)) < 0.5
        others := 0, followed := 0
        for j, t in movers {
            if (j = i || !IsObject(before[j]) || Abs(t.xa - s.xa) < 8)
                continue
            others++
            if (ReadXY(t.xa, x, y) && Abs(x - before[j][1] - 3) < 0.5 && Abs(y - before[j][2] - 3) < 0.5)
                followed++
        }
        WriteFloat(s.xa, x0)            ; put the camera back
        WriteFloat(s.xa + 4, y0)
        Sleep, 250
        if (ok && (others = 0 || followed > 0)) {
            g_LastScan .= " picked #" i " (confirmed, " followed " copies followed)"
            return s
        }
        if (ok && !persistOnly)
            persistOnly := s, persistIdx := i
    }
    if (IsObject(persistOnly) && allowUnconfirmed) {   ; kept our write but no copy followed - best remaining guess
        g_LastScan .= " picked #" persistIdx " (UNCONFIRMED)"
        return persistOnly
    }
    g_LastScan .= " write-tested=" tested " (none confirmed)"
    return 0
}

SnapPairs(cands) {
    out := []
    for i, cd in cands
        out[i] := ReadXY(cd.xa, x, y) ? [x, y] : 0
    return out
}

ReadRaw(addr, ByRef buf, size) {
    VarSetCapacity(buf, size, 0)
    return DllCall("ReadProcessMemory", "Ptr", g_h, "Ptr", addr, "Ptr", &buf, "UPtr", size, "Ptr", 0)
}

; Static floats in zoom range that go one way on wheel-up and back on wheel-down.
FindZoom(ranges) {
    offs := [], v0 := []
    for i, r in ranges {
        size := r[2] - r[1]
        o := [], vals := []
        if (size >= 4 && ReadBlockLoose(g_ModBase + r[1], buf, size)) {
            off := 0
            while (off <= size - 4) {
                f := NumGet(buf, off, "Float")
                if (f >= 0.1 && f <= 5.0)
                    o.Push(off), vals.Push(f)
                off += 4
            }
        }
        offs.Push(o), v0.Push(vals)
    }
    SendInput {WheelUp 3}
    Sleep, 900
    v1 := RereadFloats(ranges, offs)
    SendInput {WheelDown 3}
    Sleep, 900
    v2 := RereadFloats(ranges, offs)

    best := 0, bestScore := -1
    for i, r in ranges {
        for j, off in offs[i] {
            d1 := v1[i][j] - v0[i][j], d2 := v2[i][j] - v1[i][j]
            if (Abs(d1) < 0.01 || Abs(d2) < 0.01 || d1 * d2 >= 0)
                continue
            addr := r[1] + off
            score := Abs(addr - HintZoom) + (d1 > 0 ? 0 : 0x10000000)   ; prefer "zoom in => value up"
            if (bestScore < 0 || score < bestScore)
                best := addr, bestScore := score
        }
    }
    return best
}

RereadFloats(ranges, offs) {
    out := []
    for i, r in ranges {
        vals := []
        if (offs[i].Length() && ReadBlockLoose(g_ModBase + r[1], buf, r[2] - r[1])) {
            for j, off in offs[i]
                vals.Push(NumGet(buf, off, "Float"))
        }
        out.Push(vals)
    }
    return out
}

HoldKey(k, ms) {
    SendInput {%k% down}
    Sleep, %ms%
    SendInput {%k% up}
    Sleep, 250
}

Clip(secs, a, b) {
    out := []
    a := a & ~7
    for i, s in secs {
        lo := s[1] > a ? s[1] : a
        hi := s[2] < b ? s[2] : b
        if (hi - lo >= 8)
            out.Push([lo, hi])
    }
    return out
}

; =============================================================================
;  Memory helpers
; =============================================================================
ResolveCam(staticAddr) {
    p := ReadPtr(staticAddr)
    if (!IsPtr(p))
        return 0
    c := ReadPtr(p + g_Hop)
    if (!IsPtr(c) || !ReadXY(c + g_XOff, x, y) || !PlausibleXY(x, y))
        return 0
    return c
}

IsPtr(v) {
    return (v >= 0x10000 && v <= 0x7FFFFFFEFFFF && !(v & 7))
}

PlausibleXY(x, y) {
    return (x > -20 && x < MaxMapCoord && y > -20 && y < MaxMapCoord && (x != 0 || y != 0))
}

ReadPtr(addr) {
    VarSetCapacity(b, 8, 0)
    if !DllCall("ReadProcessMemory", "Ptr", g_h, "Ptr", addr, "Ptr", &b, "UPtr", 8, "Ptr", 0)
        return 0
    return NumGet(b, 0, "Int64")
}

ReadXY(addr, ByRef x, ByRef y) {
    VarSetCapacity(b, 8, 0)
    if !DllCall("ReadProcessMemory", "Ptr", g_h, "Ptr", addr, "Ptr", &b, "UPtr", 8, "Ptr", 0)
        return false
    x := NumGet(b, 0, "Float"), y := NumGet(b, 4, "Float")
    return true
}

ReadFloat(addr) {
    VarSetCapacity(b, 4, 0)
    DllCall("ReadProcessMemory", "Ptr", g_h, "Ptr", addr, "Ptr", &b, "UPtr", 4, "Ptr", 0)
    return NumGet(b, 0, "Float")
}

WriteFloat(addr, value) {
    VarSetCapacity(b, 4, 0)
    NumPut(value, b, 0, "Float")
    return DllCall("WriteProcessMemory", "Ptr", g_h, "Ptr", addr, "Ptr", &b, "UPtr", 4, "Ptr", 0)
}

; Reads a block; if the one-shot read fails, falls back to page-by-page (unreadable pages stay zero).
ReadBlockLoose(addr, ByRef buf, size) {
    VarSetCapacity(buf, size, 0)
    if DllCall("ReadProcessMemory", "Ptr", g_h, "Ptr", addr, "Ptr", &buf, "UPtr", size, "Ptr", 0)
        return true
    ok := false, off := 0
    while (off < size) {
        n := 0x1000 - Mod(addr + off, 0x1000)
        if (n > size - off)
            n := size - off
        if DllCall("ReadProcessMemory", "Ptr", g_h, "Ptr", addr + off, "Ptr", &buf + off, "UPtr", n, "Ptr", 0)
            ok := true
        off += n
    }
    return ok
}

Hex(v) {
    return Format("0x{:X}", v)
}

Tip(msg, ms := 4000) {
    ToolTip, %msg%
    if (ms)
        SetTimer, ClearTip, -%ms%
}

ClearTip:
    ToolTip
return
