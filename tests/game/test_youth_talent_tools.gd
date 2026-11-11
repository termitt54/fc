extends Node
const Config := preload("res://game/youth_generation_config.gd")
const Tools := preload("res://game/youth_talent_tools.gd")
var passed := 0
var failed := 0
func _ready() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ",message)
func run() -> void:
	assert(OS.get_user_data_dir().replace("\\","/").ends_with("/fc-load-benchmark"))
	Config.birth_config_path = "user://tests/talent-tools.json"
	Config.reset_birth_to_defaults(false)
	var defaults := Config.default_birth_weights()
	for t in 101:
		var row: Array = defaults[t]
		check(Tools.normalise(row)==row,"Normalisation preserves an exact valid row")
		var fitted := Tools.reshape(row,Config.row_mean_potential(row),1,1,1000000)
		check(bool(fitted.ok),"All talent profiles can be fitted to their original mean")
		if fitted.ok:
			check(absf(Config.row_mean_potential(fitted.row)-Config.row_mean_potential(row))<0.05,"Fitted mean matches requested PA")
			check(int(fitted.row[-1])==100,"PA100 is kept independent at one in a million")
	check(Tools.normalise([]).is_empty(),"Empty input is rejected")
	check(Tools.normalise([0,0,0]).is_empty(),"Zero distribution is rejected")
	check(Tools.normalise([1,1,1],100)==[34,33,33],"Largest remainders preserve exact total without bias to a huge last band")
	for spread in [0.5,1.0,2.0]:
		for elite in [0.05,1.0,5.0]:
			var fitted := Tools.reshape(defaults[75],72.5,spread,elite,100000000)
			check(bool(fitted.ok),"Mean fitting supports spread and elite changes together")
			if fitted.ok:
				check(int(fitted.row[-1])==1,"One-in-100-million precision is preserved")
	check(not Tools.reshape(defaults[75],29.5,1,1,1).ok,"Impossible mean with all PA100 is rejected")
	for i in 11:
		var row := Tools.interpolate(defaults[75],defaults[85],float(i)/10)
		check(row.reduce(func(a,b): return a+b,0)==Config.BIRTH_WEIGHT_TOTAL,"Interpolation preserves 100 percent exactly")
		var mean := lerpf(Config.row_mean_potential(defaults[75]),Config.row_mean_potential(defaults[85]),float(i)/10)
		check(absf(Config.row_mean_potential(row)-mean)<0.0001,"Interpolated distribution has interpolated expected PA")
	check(Tools.progression_warnings(defaults).is_empty(),"Recommended scale never drops in expected PA")
	var reversed := defaults.duplicate(true)
	reversed[85] = defaults[0].duplicate()
	check(85 in Tools.progression_warnings(reversed),"Downward breaks in talent scale are identified")
	var forecast := Tools.forecast(defaults[85],100000)
	var rng := RandomNumberGenerator.new()
	rng.seed = 814912
	var total := 0.0
	var strong := 0
	for i in 100000:
		var pa := Config.roll_birth_potential(85,rng)
		total += pa
		strong += int(pa>=80)
	check(absf(total/100000.0-float(forecast.mean))<0.2,"Forecast mean agrees with actual generator")
	check(absf(strong-float(forecast.thresholds[80].expected))<600,"Forecast strong-player count agrees with actual generator")
	var tab := preload("res://scenes/settings/tabs/global_pa_tab.tscn").instantiate()
	add_child(tab)
	check(tab._rows.get_child_count()==101,"All 101 editable levels are retained")
	var visible_rows := 0
	for row in tab._rows.get_children():
		visible_rows += int(row.visible)
	check(visible_rows==2,"Focused editor displays selected and compared talent")
	check(tab._forecast_label.text.contains("Талант 85") and tab._forecast_label.text.contains("Талант 75"),"Forecast compares the chosen levels")
	var original_runtime := Config.editor_birth_weights()
	tab._mean.value = 76.0
	tab._one_in.value = 1000000
	tab._reshape_selected()
	check(absf(Config.row_mean_potential(tab._selected_row(85))-76)<0.05,"Profile tool edits the selected row")
	check(tab._selected_row(75)==defaults[75],"Profile tool leaves other talents intact")
	check(Config.editor_birth_weights()==original_runtime,"Unsaved editing cannot affect actual player births")
	tab._interpolate_selected()
	check(absf(Config.row_mean_potential(tab._selected_row(80))-(Config.row_mean_potential(defaults[75])+76)/2)<0.05,"Intermediate talents use the two chosen boundaries")
	tab._undo_tool()
	check(tab._selected_row(80)==defaults[80],"Undo restores all rows affected by interpolation")
	tab._on_save_pressed()
	Config.unload_birth()
	check(absf(Config.row_mean_potential(Config.birth_weights(85))-76)<0.05,"Saved profile is used after reloading generation settings")
	check(Config.birth_weights(75)==defaults[75],"Saving preserves unrelated talents")
	tab.queue_free()
	DirAccess.remove_absolute(Config.birth_config_path)
	Config.birth_config_path = Config.DEFAULT_BIRTH_CONFIG_PATH
	Config.reset_birth_to_defaults(false)
	print("=== Youth talent tools: %d passed, %d failed ===" % [passed,failed])
	get_tree().quit(1 if failed else 0)
