package game

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

GAME_WIDTH :: 750
GAME_HEIGHT :: 750
PLAYER_WIDTH :: 32
PLAYER_HEIGHT :: 32

GROUND_LEVEL :: GAME_HEIGHT * 0.66

GRAVITY :: 0.5

MOVE_SPEED :: 4.0
JUMP_SPEED :: -16

JUMP_STRETCH_FACTOR :: 0.3
JUMP_STRETCH_ANIM_DURATION :: .2
STRETCH_SMOOTHING :: 20

SQUASH_SMOOTHING :: 5
SQUASH_FACTOR :: 0.25

Game_State :: struct {
	player: Player,
}

Player :: struct {
	pos:       rl.Vector2,
	size:      rl.Vector2,
	movement:  rl.Vector2,
	on_ground: bool,
}


state: Game_State

main :: proc() {
	state.player = Player {
		pos  = {GAME_WIDTH / 2, 100},
		size = {PLAYER_WIDTH, PLAYER_HEIGHT},
	}
	rl.InitWindow(750, 750, "Jump Game")
	rl.SetTargetFPS(60)

	for !rl.WindowShouldClose() {
		handle_input()
		update_player()
		rl.BeginDrawing()
		rl.ClearBackground(rl.RAYWHITE)
		draw_player()
		draw_ground()
		rl.EndDrawing()
	}
}

update_player :: proc() {
	state.player.movement.y += GRAVITY

	speed := min(abs(state.player.movement.y) / abs(f32(JUMP_SPEED)), 1)
	stretch := speed * JUMP_STRETCH_FACTOR

	target := rl.Vector2{PLAYER_WIDTH * (1 - stretch), PLAYER_HEIGHT * (1 + stretch)}
	t := min(
		rl.GetFrameTime() * (state.player.on_ground ? SQUASH_SMOOTHING : STRETCH_SMOOTHING),
		1,
	)
	state.player.size += (target - state.player.size) * t

	state.player.pos += state.player.movement
	state.player.on_ground = state.player.pos.y >= GROUND_LEVEL

	if state.player.on_ground {
		state.player.pos.y = GROUND_LEVEL

		if state.player.movement.y > 6 {
			impact := min(state.player.movement.y / abs(f32(JUMP_SPEED)), 1)
			squash := impact * SQUASH_FACTOR
			state.player.size = {PLAYER_WIDTH * (1 + squash), PLAYER_HEIGHT * (1 - squash)}
		}

		state.player.movement.y = 0
	}

}

handle_input :: proc() {
	state.player.movement.x = 0
	if (rl.IsKeyDown(rl.KeyboardKey.UP) || rl.IsKeyDown(rl.KeyboardKey.W)) &&
	   state.player.on_ground {
		state.player.movement.y = JUMP_SPEED
	}
	if rl.IsKeyDown(rl.KeyboardKey.RIGHT) || rl.IsKeyDown(rl.KeyboardKey.D) do state.player.movement.x += MOVE_SPEED
	if rl.IsKeyDown(rl.KeyboardKey.LEFT) || rl.IsKeyDown(rl.KeyboardKey.A) do state.player.movement.x -= MOVE_SPEED
}

draw_player :: proc() {
	draw_pos := rl.Vector2 {
		state.player.pos.x - state.player.size.x / 2,
		state.player.pos.y - state.player.size.y,
	}
	rl.DrawRectangleV(draw_pos, state.player.size, rl.BLACK)
}

draw_ground :: proc() {
	rl.DrawLineEx({0, GROUND_LEVEL}, {GAME_WIDTH, GROUND_LEVEL}, 3, rl.BLACK)
}
