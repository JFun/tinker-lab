extends Node
## Ad stub. Returns success immediately so the rewarded-video flow is testable
## without a real ad SDK. Wire AdMob/Unity Ads via plugin post-MVP.

signal rewarded_finished(success: bool)
signal interstitial_finished

var _last_interstitial_unix: int = 0
const INTERSTITIAL_COOLDOWN := 300  # 5 min

func show_rewarded(reward_id: String) -> void:
	# In a real build, present a video and emit on close.
	# print("[ads] rewarded shown: ", reward_id)
	rewarded_finished.emit(true)

func show_interstitial() -> bool:
	var now := int(Time.get_unix_time_from_system())
	if now - _last_interstitial_unix < INTERSTITIAL_COOLDOWN:
		return false
	_last_interstitial_unix = now
	# print("[ads] interstitial shown")
	interstitial_finished.emit()
	return true
