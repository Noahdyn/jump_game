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

// Keep obstacle edges on whole pixels (750 * 0.75 = 562.5 would put them on half pixels).
OBSTACLE_X :: GAME_WIDTH * 3 / 4

GRAVITY :: 1800

JUMP_CUT_FACTOR :: 0.5

MOVE_SPEED :: 440
JUMP_SPEED :: -866


GROUND_ACCEL :: 2400
GROUND_FRICTION :: 3000
AIR_ACCEL :: 1000
AIR_DRAG :: 0

JUMP_STRETCH_FACTOR :: 0.35
JUMP_STRETCH_ANIM_DURATION :: .2
STRETCH_SMOOTHING :: 20

SQUASH_SMOOTHING :: 8
SQUASH_FACTOR: f32 : 0.55
SQUASH_THRESHOLD :: 360

SIZE_SNAP_EPSILON :: 0.25

JUMP_PARTICLE_STRENGTH :: 0.2
LANDING_PARTICLE_STRENGTH :: 0.4

MAX_PARTICLES :: 256

MAX_OBSTACLES :: 256

MAX_IMPACT_SPEED :: 1200


Game_State :: struct {
	player:               Player,
	particle_ring_buffer: Particle_Ring_Buffer,
	obstacles:            [MAX_OBSTACLES]Obstacle,
	obstacle_count:       u16,
	camera:               rl.Camera2D,
}

Player :: struct {
	pos:           rl.Vector2,
	size:          rl.Vector2,
	vel:           rl.Vector2,
	on_ground:     bool,
	air_jumps:     u8,
	input_x:       f32,
	collision_box: rl.Rectangle,
}

Obstacle :: struct {
	pos:   rl.Vector2,
	size:  rl.Vector2,
	color: rl.Color,
}

Particle_Ring_Buffer :: struct {
	particles: [MAX_PARTICLES]Particle,
	next:      int,
}

Particle :: struct {
	pos:          rl.Vector2,
	size:         rl.Vector2,
	lifetime:     f32,
	max_lifetime: f32,
	dir_x:        f32,
	curve:        f32,
	dir:          proc(x: f32, dir_x: f32, curve: f32) -> rl.Vector2,
	speed:        f32,
	active:       bool,
}

Collision_Result :: struct {
	hit_ceiling, hit_wall, hit_floor: bool,
}

state: Game_State

main :: proc() {
	state.player = Player {
		pos  = {GAME_WIDTH / 2, 100},
		size = {PLAYER_WIDTH, PLAYER_HEIGHT},
	}

	state.obstacles[state.obstacle_count] = Obstacle {
		size  = {30, 50},
		pos   = {OBSTACLE_X, GROUND_LEVEL},
		color = rl.RED,
	}
	state.obstacle_count += 1

	state.obstacles[state.obstacle_count] = Obstacle {
		size  = {100000, GAME_HEIGHT - GROUND_LEVEL},
		pos   = {OBSTACLE_X, GAME_HEIGHT},
		color = rl.DARKGRAY,
	}
	state.obstacle_count += 1

	state.camera = rl.Camera2D{}
	state.camera.target = state.player.pos - {0, state.player.size.y + GAME_HEIGHT * 0.15}
	state.camera.offset = {GAME_WIDTH / 2, GAME_HEIGHT / 2}
	state.camera.zoom = 1.0
	state.camera.rotation = 0.0

	rl.InitWindow(GAME_WIDTH, GAME_HEIGHT, "Jump Game")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	dt: f32
	for !rl.WindowShouldClose() {
		dt = rl.GetFrameTime()
		camera_speed := dt * 5.0
		state.camera.target.x += (state.player.pos.x - state.camera.target.x) * camera_speed
		state.camera.target.y +=
			((state.player.pos.y - (state.player.size.y + GAME_HEIGHT * 0.15)) -
				state.camera.target.y) *
			camera_speed
		handle_input()
		update_player(dt)
		update_particles(dt)
		rl.BeginDrawing()
		rl.BeginMode2D(state.camera)
		rl.ClearBackground(rl.RAYWHITE)
		draw_player()
		draw_obstacles()
		draw_particles()
		rl.EndMode2D()
		rl.EndDrawing()
	}
}

update_player :: proc(dt: f32) {
	p := &state.player
	p.vel.y += GRAVITY * dt

	stretch: f32 = 0
	if !p.on_ground {
		speed := min(abs(p.vel.y) / abs(f32(JUMP_SPEED)), 1)
		stretch = speed * JUMP_STRETCH_FACTOR
	}

	target_size := rl.Vector2{PLAYER_WIDTH * (1 - stretch), PLAYER_HEIGHT * (1 + stretch)}
	t := min(dt * (p.on_ground ? SQUASH_SMOOTHING : STRETCH_SMOOTHING), 1)
	p.size += (target_size - p.size) * t
	if abs(p.size.x - target_size.x) < SIZE_SNAP_EPSILON &&
	   abs(p.size.y - target_size.y) < SIZE_SNAP_EPSILON {
		p.size = target_size
	}

	target := p.input_x * MOVE_SPEED
	accel: f32
	if p.on_ground {
		accel = p.input_x != 0 ? GROUND_ACCEL : GROUND_FRICTION
	} else {
		accel = p.input_x != 0 ? AIR_ACCEL : AIR_DRAG
	}
	p.vel.x = move_toward(p.vel.x, target, accel * dt)

	collision := move_and_collide(&p.pos, &p.vel, {PLAYER_WIDTH, PLAYER_HEIGHT}, dt)

	p.on_ground = collision.hit_floor

	if p.on_ground {
		p.air_jumps = 1
		if p.vel.y > SQUASH_THRESHOLD {
			spawn_particles(impact_strength(p.vel.y), arc_particle_fn)
			squash := SQUASH_FACTOR
			p.size = {PLAYER_WIDTH * (1 + squash), PLAYER_HEIGHT * (1 - squash)}
		}
		p.vel.y = 0
	}
}

move_toward :: proc(current, target, max_delta: f32) -> f32 {
	if abs(target - current) <= max_delta do return target
	return current + math.sign(target - current) * max_delta
}

move_and_collide :: proc(
	pos, vel: ^rl.Vector2,
	size: rl.Vector2,
	dt: f32,
) -> (
	res: Collision_Result,
) {
	solids := state.obstacles[:state.obstacle_count]

	pos.x += vel.x * dt
	for o in solids {
		ob := aabb(o.pos, o.size)
		if !rl.CheckCollisionRecs(aabb(pos^, size), ob) do continue
		if vel.x > 0 do pos.x = ob.x - size.x / 2
		else do pos.x = ob.x + ob.width + size.x / 2
		vel.x = 0
		res.hit_wall = true
	}

	pos.y += vel.y * dt
	for o in solids {
		ob := aabb(o.pos, o.size)
		if !rl.CheckCollisionRecs(aabb(pos^, size), ob) do continue
		if vel.y >
		   0 {pos.y = ob.y;res.hit_floor = true} else {pos.y = ob.y + ob.height + size.y;res.hit_ceiling = true}
		//doesnt set vel.y 0 cause ground handling does that
	}
	return
}

impact_strength :: proc(vel_y: f32) -> f32 {
	t := (vel_y - SQUASH_THRESHOLD) / (MAX_IMPACT_SPEED - SQUASH_THRESHOLD)
	return clamp(t, 0, 1)
}

aabb :: proc(pos, size: rl.Vector2) -> rl.Rectangle {
	return {pos.x - size.x / 2, pos.y - size.y, size.x, size.y}
}

spawn_particles :: proc(
	strength: f32,
	dir_fn: proc(x: f32, dir_x: f32, curve: f32) -> rl.Vector2,
) {
	rb := &state.particle_ring_buffer
	particle_count := int(4 + 8 * strength)
	for i in 0 ..< particle_count {
		side: f32 = i % 2 == 0 ? -1 : 1
		size := rand.float32_range(7, 12) * (0.7 + strength * 0.6)

		p := &rb.particles[rb.next]
		rb.next = (rb.next + 1) % MAX_PARTICLES

		p^ = Particle {
			pos          = {
				state.player.pos.x + side * state.player.size.x + rand.float32_range(-6, 6),
				state.player.pos.y - size / 2 + rand.float32_range(-1, 0),
			},
			dir          = dir_fn,
			speed        = rand.float32_range(50, 110) * (0.5 + strength),
			dir_x        = side,
			curve        = 6 + f32(rand.int_range(-5, 5)),
			max_lifetime = rand.float32_range(1.0, 1.75),
			size         = size,
			active       = true,
		}
		p.lifetime = p.max_lifetime
	}
}

quad_ease_out_particle_fn :: proc(x: f32, dir_x: f32, curve: f32) -> rl.Vector2 {
	decay := (1 - x) * (1 - x)
	return rl.Vector2{dir_x, -1} * decay
}

arc_particle_fn :: proc(x: f32, dir_x: f32, curve: f32) -> rl.Vector2 {
	return {dir_x, -1.5 + curve * x}
}

handle_input :: proc() {
	state.player.input_x = 0
	if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) do state.player.input_x += 1
	if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) do state.player.input_x -= 1

	if (rl.IsKeyPressed(rl.KeyboardKey.UP) || rl.IsKeyPressed(rl.KeyboardKey.W)) &&
	   (state.player.on_ground || state.player.air_jumps > 0) {
		if !state.player.on_ground {
			state.player.air_jumps -= 1
			state.player.vel.x = state.player.input_x * MOVE_SPEED
		}
		state.player.vel.y = JUMP_SPEED
		spawn_particles(JUMP_PARTICLE_STRENGTH, quad_ease_out_particle_fn)
	}
	if (rl.IsKeyReleased(rl.KeyboardKey.W) || rl.IsKeyReleased(rl.KeyboardKey.UP)) &&
	   state.player.vel.y < 0 {
		state.player.vel.y *= JUMP_CUT_FACTOR
	}

}

draw_player :: proc() {
	p := state.player
	draw_pos := rl.Vector2{p.pos.x - p.size.x / 2, p.pos.y - p.size.y}
	rl.DrawRectangleV(draw_pos, p.size, rl.BLACK)
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
		vel := p.dir(x, p.dir_x, p.curve)
		p.pos += vel * p.speed * dt
	}
}

draw_particles :: proc() {
	for p in state.particle_ring_buffer.particles {
		if !p.active do continue

		t := p.lifetime / p.max_lifetime
		alpha := u8(180 * t * t)

		draw_pos := rl.Vector2{p.pos.x - p.size.x / 2, p.pos.y - p.size.y / 2}

		rl.DrawRectangleV(draw_pos, p.size, rl.Color{237, 169, 200, alpha})
	}
}

draw_obstacles :: proc() {
	for i in 0 ..< state.obstacle_count {
		o := state.obstacles[i]
		draw_pos := rl.Vector2{o.pos.x - o.size.x / 2, o.pos.y - o.size.y}
		rl.DrawRectangleV(draw_pos, o.size, o.color)
	}
}
