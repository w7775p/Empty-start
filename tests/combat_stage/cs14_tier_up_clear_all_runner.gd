extends SceneTree

var _presentation_assets: PresentationAssetConfig


func _initialize() -> void:
	call_deferred("_run_smoke_scene")


# 先加载 Sandbox 共用的立绘资源，再启动聚焦场景，兼容全新 worktree 的首次资源导入。
func _run_smoke_scene() -> void:
	_presentation_assets = load("res://data/shared/presentation_asset_config.tres") as PresentationAssetConfig
	if _presentation_assets == null:
		push_error("CS-14 runner: 无法加载 Sandbox 共用立绘资源。")
		quit(1)
		return
	var smoke_scene: PackedScene = load("res://tests/combat_stage/cs14_tier_up_clear_all_smoke.tscn") as PackedScene
	if smoke_scene == null:
		push_error("CS-14 runner: 无法加载清屏聚焦场景。")
		quit(1)
		return
	root.add_child(smoke_scene.instantiate())
