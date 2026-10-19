extends Node
## The rearguard at the foot of the cliff path (between the two halves of
## the retreat cutscene, retreat.gd): more lizards come on after the
## volley, the sergeant calls for bayonets and a charge, and you play it in
## first person. It is the bayonet lesson: fix the bayonet, strike from a
## side (hold, let go), block when one rears up glowing, then finish them.
## Nothing here counts on the books (no pay, no losses): when it's over, the
## retreat cutscene carries on (Engine meta "retreat_resume").

const RETREAT := "res://scenes/retreat.tscn"

var field
var battle
var you
var foes: Array = []
var step := 0 # 0 fix bayonets, 1 the charge (strike), 2 block, 3 finish them, 4 over
var t := 0.0
var step_t := 0.0
var hits := 0
var blocks := 0
var _over_t := -1.0


func _init(f) -> void:
	field = f
	battle = f.battle
	name = "Rearguard"


func spawn() -> void:
	var men: Array = Company.fit_men().filter(func(m): return String(m.get("tag", "")) != "Wagon")
	# Your line across the foot of the path, facing back down the beach; the
	# lizards coming along the sand from the west.
	var at := Vector3(60.0, 0, 18.0)
	you = field._make_reg(0, "musket", maxi(1, men.size()), at, Vector3.LEFT, true, men)
	you.title = Lang.t("Your company")
	you.fire_at_will = false
	you.order_hold()
	foes.append(field._make_reg(1, "liz_warrior", 10, Vector3(10.0, 0, 15.0), Vector3.RIGHT, false))
	foes.append(field._make_reg(1, "liz_warrior", 8, Vector3(0.0, 0, 23.0), Vector3.RIGHT, false))
	for r in foes:
		r.order_attack(you)
		if field.ui != null:
			field.ui.add_banner(r)
	var p: Vector3 = you.pos
	battle.player.position = Vector3(p.x, field.terrain.height(p.x, p.z) + 0.3, p.z)
	battle.player.rotation.y = atan2(1.0, 0.0) # (facing west, down the beach)
	battle.line_anchor = Vector3(p.x, 0, p.z)
	battle.line_forward = Vector3.LEFT
	battle._commanding = true
	battle.say(battle._sergeant_name(), Lang.t("More of them! Fix bayonets, lads! Fix bayonets!"), 3.5)


func _process(delta: float) -> void:
	if battle.hud == null or step >= 4:
		_tick_over(delta)
		return
	t += delta
	step_t += delta
	var pl = battle.player
	match step:
		0:
			battle.hud.show_hint(Lang.t("FIX BAYONETS: change to the bayonet (the weapon buttons). It takes a moment to fix."), 0.3)
			if pl.weapon == "melee" or step_t > 9.0:
				if pl.weapon != "melee":
					pl.switch_to("melee")
				_next()
				battle.say(battle._sergeant_name(), Lang.t("Charge! Charge! Into them!"), 3.0)
				for f in foes:
					if not f.gone():
						you.order_charge(f)
						break
		1:
			battle.hud.show_hint(Lang.t("THE CHARGE: run at them with your men. Hold OVER, LEFT, RIGHT or THRUST to wind up a blow from that side, let go to strike. (%d of 3)") % mini(hits, 3), 0.3)
			if hits >= 3 or step_t > 30.0:
				_next()
		2:
			battle.hud.show_hint(Lang.t("BLOCK: when one rears up glowing, hold BLOCK until it strikes, then hit back. (%d of 1)") % mini(blocks, 1), 0.3)
			if blocks >= 1 or step_t > 20.0:
				_next()
		3:
			battle.hud.show_hint(Lang.t("Finish them! Drive them back down the beach."), 0.3)
	if step >= 1 and you.order != "charge" and not you.broken():
		# (keep the line going in until it's done)
		for f in foes:
			if not f.gone() and not f.broken():
				you.order_charge(f)
				break
	# Done when they're all down or running.
	var left := 0
	for f in foes:
		if not f.gone() and not f.broken():
			left += 1
	if left == 0 and step >= 1:
		end(true)


func _next() -> void:
	step += 1
	step_t = 0.0


## The player's blows and blocks (player.gd signals).
func on_hit(_count: int) -> void:
	hits += 1


func on_block() -> void:
	blocks += 1


func player_down() -> void:
	battle.hud.show_message(Lang.t("You go down in the press. Your men drag you up the path."), 3.0)
	end(false)


## Over: a moment on the field, then back to the retreat.
func end(won: bool) -> void:
	if step >= 4:
		return
	step = 4
	field.over = "won" if won else "lost"
	battle.victory = won
	battle.game_state = "won" if won else "lost"
	if won:
		battle.hud.show_message(Lang.t("They break and run back down the beach!"), 3.0)
		battle.say(battle._sergeant_name(), Lang.t("Let them go! Up the path, all of you!"), 3.0)
	_over_t = 3.2


func _tick_over(delta: float) -> void:
	if _over_t < 0.0:
		return
	_over_t -= delta
	if _over_t <= 0.0:
		_over_t = -1.0
		Company.next_battle = {}
		Engine.set_meta("retreat_resume", true)
		Loading.change(RETREAT)
