package game

import "core:fmt"
import "core:math"
import rand "core:math/rand"
import rl "vendor:raylib"

GAME_WIDTH :: 750
GAME_HEIGHT :: 750
PLAYER_WIDTH :: 32
PLAYER_HEIGHT :: 32

GROUND_LEVEL :: GAME_HEIGHT * 0.66

GRAVITY :: 1800

MOVE_SPEED :: 240
JUMP_SPEED :: -960

JUMP_STRETCH_FACTOR :: 0.3
JUMP_STRETCH_ANIM_DURATION :: .2
STRETCH_SMOOTHING :: 20

SQUASH_SMOOTHING :: 5
SQUASH_FACTOR :: 0.25
SQUASH_THRESHHOLD :: 360

MAX_PARTICLES :: 256

Game_State :: struct {
	player:               Player,
	particle_ring_buffer: Particle_Ring_Buffer,
}

Player :: struct {
	pos:       rl.Vector2,
	size:      rl.Vector2,
	vel:       rl.Vector2,
	on_ground: bool,
}

//TODO: particles: jumping: particles poitned upwards (like current implementation) | landing: particles go in a curve, raise briefly then drop

Particle_Ring_Buffer :: struct {
	particles: [MAX_PARTICLES]Particle,
	next:      int,
}

Particle :: struct {
	pos:          rl.Vector2,
	size:         rl.Vector2,
	lifetime:     f32,
	max_lifetime: f32,
	invert:       bool,
	dir:          proc(x: f32, pos: rl.Vector2, invert: bool) -> rl.Vector2,
	speed:        f32,
	active:       bool,
}


state: Game_State

main :: proc() {
	state.player = Player {
		pos  = {GAME_WIDTH / 2, 100},
		size = {PLAYER_WIDTH, PLAYER_HEIGHT},
	}
	rl.InitWindow(750, 750, "Jump Game")
	rl.SetTargetFPS(60)

	dt: f32
	for !rl.WindowShouldClose() {
		dt = rl.GetFrameTime()
		handle_input()
		update_player(dt)
		update_particles(dt)
		rl.BeginDrawing()
		rl.ClearBackground(rl.RAYWHITE)
		draw_player()
		draw_ground()
		draw_particles()
		rl.EndDrawing()
	}
}

update_player :: proc(dt: f32) {
	state.player.vel.y += GRAVITY * dt

	speed := min(abs(state.player.vel.y) / abs(f32(JUMP_SPEED)), 1)
	stretch := speed * JUMP_STRETCH_FACTOR

	target := rl.Vector2{PLAYER_WIDTH * (1 - stretch), PLAYER_HEIGHT * (1 + stretch)}
	t := min(dt * (state.player.on_ground ? SQUASH_SMOOTHING : STRETCH_SMOOTHING), 1)
	state.player.size += (target - state.player.size) * t

	if state.player.on_ground && state.player.vel.y < 4 {
		strength: f32 = 0.2
		spawn_jump_particles(strength)
	}

	state.player.pos += state.player.vel * dt

	state.player.on_ground = state.player.pos.y >= GROUND_LEVEL

	if state.player.on_ground {
		state.player.pos.y = GROUND_LEVEL

		if state.player.vel.y > SQUASH_THRESHHOLD {
			spawn_landing_particles(0.2)
			impact := min(state.player.vel.y / abs(f32(JUMP_SPEED)), 1)
			squash := impact * SQUASH_FACTOR
			state.player.size = {PLAYER_WIDTH * (1 + squash), PLAYER_HEIGHT * (1 - squash)}
		}
		state.player.vel.y = 0
	}
}

spawn_jump_particles :: proc(strength: f32) {
	//todo: dont have them only go angled up, some down is also ok
	particle_count := int(4 + 8 * strength)
	for i in 0 ..< particle_count {
		dir: f32 = i % 2 == 0 ? -1 : 1
		speed := rand.float32_range(50, 110) * (0.5 + strength)

		rb := &state.particle_ring_buffer
		p := &rb.particles[rb.next]
		rb.next = (state.particle_ring_buffer.next + 1) % MAX_PARTICLES

		p^ = Particle {
			pos          = {
				state.player.pos.x +
				(dir == -1 ? (-state.player.size.x) : state.player.size.x) +
				rand.float32_range(-6, 6),
				state.player.pos.y + rand.float32_range(-1, 0),
			},
			dir          = linear_particle_fn,
			speed        = speed,
			invert       = dir == -1,
			max_lifetime = rand.float32_range(1.0, 1.75),
			size         = rand.float32_range(7, 12) * (0.7 + strength * 0.6),
			active       = true,
		}
		p.lifetime = p.max_lifetime
	}
}

linear_particle_fn :: proc(x: f32, pos: rl.Vector2, invert: bool) -> rl.Vector2 {
	return {invert ? -1 : 1, -1}
}

arc_particle_fn :: proc(x: f32, pos: rl.Vector2, invert: bool) -> rl.Vector2 {
	return {invert ? -1 : 1, -1.5 + 4 * x}
}

spawn_landing_particles :: proc(strength: f32) {
	particle_count := int(4 + 8 * strength)
	for i in 0 ..< particle_count {
		dir: f32 = i % 2 == 0 ? -1 : 1
		speed := rand.float32_range(50, 110) * (0.5 + strength)

		rb := &state.particle_ring_buffer
		p := &rb.particles[rb.next]
		rb.next = (state.particle_ring_buffer.next + 1) % MAX_PARTICLES

		p^ = Particle {
			pos          = {
				state.player.pos.x +
				(dir == -1 ? (-state.player.size.x) : state.player.size.x) +
				rand.float32_range(-6, 6),
				state.player.pos.y + rand.float32_range(-1, 0),
			},
			dir          = arc_particle_fn,
			speed        = speed,
			invert       = dir == -1,
			max_lifetime = rand.float32_range(1.0, 1.75),
			size         = rand.float32_range(7, 12) * (0.7 + strength * 0.6),
			active       = true,
		}
		p.lifetime = p.max_lifetime
	}
}

handle_input :: proc() {
	state.player.vel.x = 0
	if (rl.IsKeyDown(rl.KeyboardKey.UP) || rl.IsKeyDown(rl.KeyboardKey.W)) &&
	   state.player.on_ground {
		state.player.vel.y = JUMP_SPEED
	}
	if rl.IsKeyDown(rl.KeyboardKey.RIGHT) || rl.IsKeyDown(rl.KeyboardKey.D) do state.player.vel.x += MOVE_SPEED
	if rl.IsKeyDown(rl.KeyboardKey.LEFT) || rl.IsKeyDown(rl.KeyboardKey.A) do state.player.vel.x -= MOVE_SPEED
}

draw_player :: proc() {
	draw_pos := rl.Vector2 {
		state.player.pos.x - state.player.size.x / 2,
		state.player.pos.y - state.player.size.y,
	}
	rl.DrawRectangleV(draw_pos, state.player.size, rl.BLACK)
}

update_particles :: proc(dt: f32) {
	for &p in state.particle_ring_buffer.particles {
		if !p.active do continue

		p.lifetime -= dt
		if p.lifetime <= 0 {
			p.active = false
			continue
		}

		if p.dir == nil do continue

		x := 1 - p.lifetime / p.max_lifetime
		dir := rl.Vector2Normalize(p.dir(x, p.pos, p.invert))

		p.speed *= math.pow(0.02, dt) // drag
		p.pos += dir * p.speed * dt
	}
}

draw_particles :: proc() {
	for p in state.particle_ring_buffer.particles {
		if !p.active do continue

		t := p.lifetime / p.max_lifetime
		size := p.size * (1.5 - t)
		alpha := u8(180 * t * t)

		draw_pos := rl.Vector2{p.pos.x - size.x / 2, p.pos.y - size.y / 2}

		rl.DrawRectangleV(draw_pos, size, rl.Color{237, 169, 66, 255})
	}
}

draw_ground :: proc() {
	rl.DrawLineEx({0, GROUND_LEVEL}, {GAME_WIDTH, GROUND_LEVEL}, 3, rl.BLACK)
}
