package filebrowser

import rl  "vendor:raylib"
import "core:fmt"
import "core:strings"
import "core:c"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:time"

// ------------------------------------------------------------
// File Browser State
// ------------------------------------------------------------
File_Browser :: struct {
    is_hidden:         bool,
    active:            bool,
    last_click_index: i32,
    last_click_time:  f64,
    // Preview
    preview_texture:   rl.Texture2D,
    has_preview:       bool,
    preview_path:      [1024]u8,   // to know when we need to reload

    bounds:            rl.Rectangle,
    
    // Path
    current_path:      [1024]u8,          // current directory
    path_edit_mode:    bool,
    
    // File list
    entries:           [dynamic]Entry,
    scroll_index:      i32,
    active_index:      i32,               // selected item
    focus_index:       i32,
    
    // Filtering
    filter_ext:        [128]u8,           // e.g. ".png;.jpg;.blend"
    search_text:       [128]u8,
    search_edit_mode:  bool,
    show_hidden:       bool,
    
    // Result
    selected_file:     [1024]u8,          // full path of selected file
    select_pressed:    bool,
    cancel_pressed:    bool,
}

Entry :: struct {
    name:     string,                     // just the filename
    full:     cstring,                     // full path
    is_dir:   bool,
    size:     i64,
    mod_time: time.Time,
}
// Free one entry
free_entry :: proc(e: ^Entry) {
    delete(e.name)
    delete(e.full)
    e^ = {}
}

// Free the whole list
clear_entries :: proc(fb: ^File_Browser) {
    for &e in fb.entries {
        free_entry(&e)
    }
    clear(&fb.entries)
}

apply_dark_mode :: proc () {
    rl.GuiSetStyle(.DEFAULT, i32(rl.GuiDefaultProperty.BACKGROUND_COLOR),
        i32(rl.ColorToInt({40, 42, 54, 255})))
    rl.GuiSetStyle(.DEFAULT, i32(rl.GuiDefaultProperty.LINE_COLOR),
        i32(rl.ColorToInt({68, 71, 90, 255})))
    rl.GuiSetStyle(.DEFAULT, i32(rl.GuiControlProperty.TEXT_COLOR_NORMAL),
        i32(rl.ColorToInt({220, 220, 220, 255})))
    // Title bar
    rl.GuiSetStyle(.STATUSBAR, i32(rl.GuiControlProperty.BASE_COLOR_NORMAL),
        i32(rl.ColorToInt({50, 52, 70, 255})))
    rl.GuiSetStyle(.STATUSBAR, i32(rl.GuiControlProperty.TEXT_COLOR_NORMAL),
        i32(rl.ColorToInt({240, 240, 255, 255})))   // ← title text color

    // Buttons
    rl.GuiSetStyle(.BUTTON, i32(rl.GuiControlProperty.BASE_COLOR_NORMAL),
        i32(rl.ColorToInt({70, 72, 100, 255})))
    rl.GuiSetStyle(.BUTTON, i32(rl.GuiControlProperty.TEXT_COLOR_NORMAL),
        i32(rl.ColorToInt({230, 230, 245, 255})))

    // ListView
    rl.GuiSetStyle(.LISTVIEW, i32(rl.GuiControlProperty.BASE_COLOR_NORMAL),
        i32(rl.ColorToInt({45, 47, 60, 255})))
    rl.GuiSetStyle(.LISTVIEW, i32(rl.GuiControlProperty.TEXT_COLOR_NORMAL),
        i32(rl.ColorToInt({210, 210, 225, 255})))
    rl.GuiSetStyle(.LISTVIEW, i32(rl.GuiControlProperty.TEXT_COLOR_FOCUSED),
        i32(rl.ColorToInt({255, 255, 255, 255})))
    rl.GuiSetStyle(.LISTVIEW, i32(rl.GuiControlProperty.BASE_COLOR_FOCUSED),
        i32(rl.ColorToInt({125, 125, 125, 255})))
    // TextBox (path bar)
    rl.GuiSetStyle(.TEXTBOX, i32(rl.GuiControlProperty.TEXT_COLOR_NORMAL),
        i32(rl.ColorToInt({230, 230, 240, 255})))
}
// ------------------------------------------------------------
// Public API
// ------------------------------------------------------------

is_image_file :: proc(path: string) -> bool {
    ext := strings.to_lower(filepath.ext(path), context.temp_allocator)
    return ext == ".png"  || ext == ".jpg"  || ext == ".jpeg" ||
           ext == ".bmp"  || ext == ".tga"  || ext == ".gif"  ||
           ext == ".psd"  || ext == ".hdr"  || ext == ".pic"
}

init_file_browser :: proc(start_path: string = "") -> File_Browser {
    fb: File_Browser
    fb.active = false
    fb.bounds = {100, 50, 720, 520}
    fb.active_index = -1
    fb.focus_index  = -1
    fb.scroll_index = 0
    fb.last_click_index = -1
    fb.last_click_time  = 0
    fb.has_preview = false
    fb.preview_texture = {}
    // rl.GuiSetStyle(.WIN)
    path := start_path
    if path == "" {
        path = string(rl.GetWorkingDirectory())
    }
    copy_to_buf(fb.current_path[:], path)
    // Default filter (empty = show all)
    image_filter := ".jpg;.png;.jpeg;.bmp;.tga;.gif"
    copy_to_buf(fb.filter_ext[:], image_filter)

    return fb
}

open_file_browser :: proc(fb: ^File_Browser, start_path: string = "") {
    fb.active = true
    fb.select_pressed = false
    fb.cancel_pressed = false
    fb.active_index = -1
    fb.focus_index  = -1
    fb.scroll_index = 0
    fb.last_click_index = -1
    fb.last_click_time  = 0
    if start_path != "" {
        copy_to_buf(fb.current_path[:], start_path)
    }
    
    refresh_directory(fb)
}
unload_preview :: proc(fb: ^File_Browser) {
    if fb.has_preview {
        rl.UnloadTexture(fb.preview_texture)
        fb.has_preview = false
        fb.preview_texture = {}
        copy_to_buf(fb.preview_path[:], "")
    }
}

update_preview :: proc(fb: ^File_Browser) {
    if fb.active_index < 0 || fb.active_index >= i32(len(fb.entries)) {
        unload_preview(fb)
        return
    }

    entry := fb.entries[fb.active_index]

    if entry.is_dir || !is_image_file(string(entry.full)) {
        unload_preview(fb)
        return
    }

    // Already showing this image? (compare content, not pointer)
    current_preview := buf_to_string(fb.preview_path[:])
    if fb.has_preview && current_preview == string(entry.full) {
        return
    }

    unload_preview(fb)

    // ---------- Robust loading ----------
    path := string(entry.full)

    // 1. Read file ourselves (avoids many path / unicode problems)
    data, ok := os.read_entire_file(path, context.temp_allocator)
    if !ok {
        fmt.eprintf("Failed to read file: %s\n", path)
        return
    }

    // 2. Force lowercase extension so Raylib accepts .JPG / .PNG / etc.
    ext := strings.to_lower(filepath.ext(path), context.temp_allocator)
    if ext == "" {
        fmt.eprintf("No extension: %s\n", path)
        return
    }
    ext_cstr := strings.clone_to_cstring(ext, context.temp_allocator)

    // 3. Load from memory
    img := rl.LoadImageFromMemory(ext_cstr, raw_data(data), i32(len(data)))
    if img.data == nil {
        fmt.eprintf("Failed to decode image: %s (ext=%s)\n", path, ext)
        return
    }
    defer rl.UnloadImage(img)

    // 4. Resize very large images
    max_size :: 1024
    if img.width > max_size || img.height > max_size {
        scale := f32(max_size) / f32(max(img.width, img.height))
        new_w := i32(f32(img.width)  * scale)
        new_h := i32(f32(img.height) * scale)
        rl.ImageResize(&img, new_w, new_h)
    }

    // 5. Create texture
    tex := rl.LoadTextureFromImage(img)
    if tex.id == 0 {
        fmt.eprintf("Failed to create texture: %s\n", path)
        return
    }

    fb.preview_texture = tex
    fb.has_preview = true
    copy_to_buf(fb.preview_path[:], path)
}
// Call this every frame. Returns true when the user confirmed a selection.
update_file_browser :: proc(fb: ^File_Browser) -> (selected: bool, path: string) {
    if !fb.active do return false, ""
    update_preview(fb)
    // Handle double-click / Enter
    if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) {
        if fb.active_index >= 0 && fb.active_index < i32(len(fb.entries)) {
            entry := fb.entries[fb.active_index]
            if entry.is_dir {
                navigate_to(fb, string(entry.full))
            } else {
                copy_to_buf(fb.selected_file[:], string(entry.full))
                fb.select_pressed = true
                fb.active = false
                return true, buf_to_string(fb.selected_file[:])
            }
        }
    }
    
    if fb.select_pressed {
        fb.select_pressed = false
        fb.active = false
        return true, buf_to_string(fb.selected_file[:])
    }
    
    if fb.cancel_pressed {
        fb.cancel_pressed = false
        fb.active = false
    }
    
    return false, ""
}

// ------------------------------------------------------------
// Drawing + Interaction
// ------------------------------------------------------------
draw_file_browser :: proc(fb: ^File_Browser) {
    @static double_click_time: f64 = 0.35
    @static preview_w: f32 = 220

    if !fb.active do return
    
    // Modal background dim
    rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.Fade(rl.BLACK, 0.45))
    
    // Main window
    // rl.DrawRectangleRec(fb.bounds, rl.GRAY)
    if rl.GuiWindowBox(fb.bounds, "#198# File Browser") != 0 {
        fb.cancel_pressed = true
    }
   
    pad: f32 = 8
    x := fb.bounds.x + pad
    y := fb.bounds.y + 28
    w := fb.bounds.width - pad*2
    
    // --- Top toolbar ---
    @static btn_w: f32 = 36
    if rl.GuiButton({x, y, btn_w, 28}, "#114#") { // Parent
        
        current := buf_to_string(fb.current_path[:])
        parent  := get_parent_dir(current)

        if parent != "" && parent != current {
            navigate_to(fb, parent)
        }
    }
    if rl.GuiButton({x + btn_w + 4, y, btn_w, 28}, "#111#") { // Home
        navigate_to(fb, string(rl.GetWorkingDirectory()))
    }
    if rl.GuiButton({x + (btn_w+4)*2, y, btn_w, 28}, "#97#") { // Refresh
        refresh_directory(fb)
    }
    
    // Path text box
    path_x := x + (btn_w+4)*3 + 8
    path_w := w - (btn_w+4)*3 - 8
    if rl.GuiTextBox({path_x, y, path_w, 28}, cstring(&fb.current_path[0]), 1024, fb.path_edit_mode) {
        fb.path_edit_mode = !fb.path_edit_mode
        if !fb.path_edit_mode {
            // User finished editing path → try to navigate
            navigate_to(fb, buf_to_string(fb.current_path[:]))
        }
    }
    
    y += 36
    
    // --- Search + Filter ---
    rl.GuiLabel({x, y, 50, 24}, "Search:")
    if rl.GuiTextBox({x+55, y, 200, 24}, cstring(&fb.search_text[0]), 128, fb.search_edit_mode) {
        fb.search_edit_mode = !fb.search_edit_mode
        refresh_directory(fb) // live filter
    }
    
    rl.GuiLabel({x+270, y, 50, 24}, "Filter:")
    if rl.GuiTextBox({x+320, y, 180, 24}, cstring(&fb.filter_ext[0]), 128, false) {
        // optional: toggle edit mode if you want
    }
    if rl.GuiButton({x+510, y, 70, 24}, "Apply") {
        refresh_directory(fb)
    }
    
    // Show hidden toggle
    rl.GuiCheckBox({x+590, y, 20, 20}, "Hidden", &fb.show_hidden)
    y += 32
    
    // --- File list ---
    list_h := fb.bounds.height - (y - fb.bounds.y) - 70
    list_bounds := rl.Rectangle{x, y, w - preview_w - 10, list_h}
    
    // Build display strings for GuiListViewEx
    display_items := make([dynamic]cstring, context.temp_allocator)
    defer delete(display_items)
    for e in fb.entries {
        prefix := e.is_dir ? "[DIR]  " : "       "
        size_str := e.is_dir ? "" : fmt.tprintf("  (%s)", format_size(e.size))
        item := fmt.ctprintf("%s%s%s", prefix, e.name, size_str)  // uses temp allocator by default in recent Odin
        append(&display_items, item)
    }
    
    // ListView
    pick := rl.GuiListViewEx(
        list_bounds,
        raw_data(display_items[:]),
        i32(len(display_items)),
        &fb.scroll_index,
        &fb.active_index,
        &fb.focus_index,
    )

   // --- Preview panel (right side) ---
    preview_bounds := rl.Rectangle{
        fb.bounds.x + fb.bounds.width - preview_w - pad,
        y,                                 // same y as list start
        preview_w,
        list_h,
    }

    // Background
    rl.GuiPanel(preview_bounds, "Preview")

    if fb.has_preview {
        // Calculate scale to fit
        tex := fb.preview_texture
        scale := min(
            (preview_bounds.width  - 16) / f32(tex.width),
            (preview_bounds.height - 40) / f32(tex.height),
        )
        if scale > 1.0 do scale = 1.0   // don't upscale small images

        draw_w := f32(tex.width)  * scale
        draw_h := f32(tex.height) * scale

        dest := rl.Rectangle{
            preview_bounds.x + (preview_bounds.width  - draw_w) * 0.5,
            preview_bounds.y + 28 + (preview_bounds.height - 40 - draw_h) * 0.5,
            draw_w,
            draw_h,
        }

        src := rl.Rectangle{0, 0, f32(tex.width), f32(tex.height)}
        rl.DrawTexturePro(tex, src, dest, {0, 0}, 0, rl.WHITE)

        // Optional: show resolution
        info := fmt.ctprintf("%d × %d", tex.width, tex.height)
        rl.GuiLabel({preview_bounds.x + 8, preview_bounds.y + preview_bounds.height - 22, preview_w - 16, 20}, info)
    } else {
        rl.GuiLabel({preview_bounds.x + 10, preview_bounds.y + preview_bounds.height/2 - 10, preview_w - 20, 20}, "No preview")
    }
    // Double-click detection
    if rl.IsMouseButtonPressed(.LEFT) {
        mouse := rl.GetMousePosition()
        if rl.CheckCollisionPointRec(mouse, list_bounds) && fb.active_index >= 0 {
            now := rl.GetTime()

            // Same item clicked twice within 0.35 seconds → double click
            if fb.active_index == fb.last_click_index && (now - fb.last_click_time) < 0.5 {
                entry := fb.entries[fb.active_index]

                if entry.is_dir {
                    navigate_to(fb, string(entry.full))
                } else {
                    copy_to_buf(fb.selected_file[:], string(entry.full))
                    fb.select_pressed = true
                }

                // Prevent triple-click triggering again immediately
                fb.last_click_index = -1
                fb.last_click_time  = 0
            } else {
                // First click of a potential double-click
                fb.last_click_index = fb.active_index
                fb.last_click_time  = now
            }
        }
    }
    
    y += list_h + 10
    
    // --- Bottom buttons ---
    btn_w2: f32 = 100
    if rl.GuiButton({x + w - btn_w2*2 - 10, y, btn_w2, 32}, "Select") {
        if fb.active_index >= 0 && fb.active_index < i32(len(fb.entries)) {
            entry := fb.entries[fb.active_index]
            if !entry.is_dir {
                copy_to_buf(fb.selected_file[:], string(entry.full))
                fb.select_pressed = true
            } else {
                // If directory selected, enter it
                navigate_to(fb, string(entry.full))
            }
        }
    }
    if rl.GuiButton({x + w - btn_w2, y, btn_w2, 32}, "Cancel") {
        fb.cancel_pressed = true
    }
    
    // Status bar
    status := fmt.ctprintf("%d items", len(fb.entries))
    rl.GuiStatusBar({x, y + 40, w, 22}, status)
}

// ------------------------------------------------------------
// Internal helpers
// ------------------------------------------------------------

navigate_to :: proc(fb: ^File_Browser, new_path: string) {
    if new_path == "" do return

    // Clean the path a bit
    clean_path := strings.trim_right(new_path, "/\\")
    cstring_clean_path := strings.clone_to_cstring(clean_path, context.temp_allocator)
    // Make sure it's actually a directory
    if !rl.DirectoryExists(cstring_clean_path) {
        fmt.eprintf("Cannot navigate to: %s (not a directory)\n", clean_path)
        return
    }

    // Copy into the fixed buffer + null-terminate
    copy_to_buf(fb.current_path[:], string(cstring_clean_path))

    // Reset list state
    fb.active_index = -1
    fb.focus_index  = -1
    fb.scroll_index = 0

    // Reload the file list
    refresh_directory(fb)
}
refresh_directory :: proc(fb: ^File_Browser) {
    // Important: free previous entries first
    clear_entries(fb)

    path_str := buf_to_string(fb.current_path[:])
    if path_str == "" do return

    if !rl.DirectoryExists(strings.clone_to_cstring(path_str, context.temp_allocator)) {
        return
    }

    list: rl.FilePathList
    filter_str := buf_to_string(fb.filter_ext[:])

    if filter_str == "" {
        list = rl.LoadDirectoryFiles(strings.clone_to_cstring(path_str, context.temp_allocator))
    } else {
        full_filter := filter_str
        if !strings.contains(filter_str, "DIR") {
            full_filter = strings.concatenate({"DIR;", filter_str}, context.temp_allocator)
        }
        list = rl.LoadDirectoryFilesEx(
            strings.clone_to_cstring(path_str, context.temp_allocator),
            strings.clone_to_cstring(full_filter, context.temp_allocator),
            false,
        )
    }
    defer rl.UnloadDirectoryFiles(list)

    search := strings.to_lower(buf_to_string(fb.search_text[:]), context.temp_allocator)

    for i in 0..<list.count {
        full_cstr := list.paths[i]
        full := string(full_cstr)
        name := filepath.base(full)

        if name == "." || name == ".." do continue
        if !fb.show_hidden && strings.has_prefix(name, ".") do continue

        if search != "" {
            name_lower := strings.to_lower(name, context.temp_allocator)
            if !strings.contains(name_lower, search) do continue
        }

        is_dir := rl.DirectoryExists(full_cstr)

        size: i64 = 0
        mod_time: time.Time
        if !is_dir {
            if info, err := os.stat(full, context.allocator); err == nil {
                size = info.size
                mod_time = info.modification_time
                os.file_info_delete(info, context.allocator)
            }
        }

        // Only these two allocations are permanent
        append(&fb.entries, Entry{
            name     = strings.clone(name),   // owned
            full     = strings.clone_to_cstring(full),   // owned
            is_dir   = is_dir,
            size     = size,
            mod_time = mod_time,
        })
    }

    // Sort
    slice.sort_by(fb.entries[:], proc(a, b: Entry) -> bool {
        if a.is_dir != b.is_dir do return a.is_dir
        return strings.to_lower(a.name, context.temp_allocator) < strings.to_lower(b.name, context.temp_allocator)
    })
}

format_size :: proc(bytes: i64) -> string {
    if bytes < 1024 {
        return fmt.tprintf("%d B", bytes)
    } else if bytes < 1024*1024 {
        return fmt.tprintf("%.1f KB", f64(bytes)/1024)
    } else if bytes < 1024*1024*1024 {
        return fmt.tprintf("%.1f MB", f64(bytes)/(1024*1024))
    }
    return fmt.tprintf("%.1f GB", f64(bytes)/(1024*1024*1024))
}

// Clean up allocated strings when closing
destroy_file_browser :: proc(fb: ^File_Browser) {
    unload_preview(fb)
    clear_entries(fb)
    delete(fb.entries)
    fb^ = {}
}

copy_to_buf :: proc(buf: []u8, s: string) {
    n := copy(buf, s)
    // Clear the rest of the buffer
    for i in n..<len(buf) {
        buf[i] = 0
    }
}

// Helper: safely turn a null-terminated [N]u8 buffer into a string
buf_to_string :: proc(buf: []u8) -> string {
    // Find the first null terminator
    for b, i in buf {
        if b == 0 {
            return string(buf[:i])
        }
    }
    return string(buf)
}

// Returns the parent directory without allocating
get_parent_dir :: proc(path: string) -> string {
    path := strings.trim_right(path, "/\\")
    if path == "" do return ""

    // Find last separator
    for i := len(path)-1; i >= 0; i -= 1 {
        if path[i] == '/' || path[i] == '\\' {
            if i == 0 {
                // root case (e.g. "/" or "C:\")
                return path[:1]
            }
            return path[:i]
        }
    }
    return ""
}