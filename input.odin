package main

// Catching quick clicks, such as trackpad taps.
//
// raylib only remembers the *latest* state of each mouse button. A tap on a
// trackpad sends "button down" and "button up" almost at the same instant, and when
// both arrive between two frames, raylib only ever sees "up": rl.IsMouseButtonPressed
// never becomes true and the tap is lost. (A physical press is fine, because the
// button stays down for several frames.)
//
// raylib is built on GLFW, a small library that talks to the operating system and
// calls a function of ours whenever a mouse button changes. We put our own function
// in front of raylib's: it counts every "down" the moment it happens, then passes the
// event on to raylib so everything else keeps working. The GLFW functions are already
// inside the raylib library that Odin links, so nothing extra is needed to build.

import rl "vendor:raylib"

when ODIN_OS == .Windows {
	foreign import raylib_library {"vendor:raylib/windows/raylib.lib"}
} else when ODIN_OS == .Darwin {
	foreign import raylib_library {"vendor:raylib/macos/libraylib.a"}
} else when ODIN_ARCH == .arm64 {
	foreign import raylib_library {"vendor:raylib/linux-arm64/libraylib.a"}
} else {
	foreign import raylib_library {"vendor:raylib/linux/libraylib.a"}
}

GLFW_PRESS :: 1

Mouse_Button_Callback :: #type proc "c" (window: rawptr, button, action, modifiers: i32)

@(default_calling_convention = "c")
foreign raylib_library {
	glfwGetCurrentContext      :: proc() -> rawptr ---
	glfwSetMouseButtonCallback :: proc(window: rawptr, callback: Mouse_Button_Callback) -> Mouse_Button_Callback ---
}

raylib_mouse_button_callback: Mouse_Button_Callback // raylib's own, which we pass events on to
left_clicks_waiting: int
right_clicks_waiting: int

// Called by GLFW for every button change, even several between two frames.
catch_mouse_button :: proc "c" (window: rawptr, button, action, modifiers: i32) {
	if action == GLFW_PRESS {
		if button == i32(rl.MouseButton.LEFT) do left_clicks_waiting += 1
		if button == i32(rl.MouseButton.RIGHT) do right_clicks_waiting += 1
	}
	if raylib_mouse_button_callback != nil {
		raylib_mouse_button_callback(window, button, action, modifiers)
	}
}

// Call once, right after rl.InitWindow.
install_click_catcher :: proc() {
	window := glfwGetCurrentContext() // the window raylib just opened
	raylib_mouse_button_callback = glfwSetMouseButtonCallback(window, catch_mouse_button)
}

// True once for every click or tap since the last frame, however short it was.
left_click_happened :: proc() -> bool {
	clicked := left_clicks_waiting > 0
	left_clicks_waiting = 0
	return clicked
}

right_click_happened :: proc() -> bool {
	clicked := right_clicks_waiting > 0
	right_clicks_waiting = 0
	return clicked
}
