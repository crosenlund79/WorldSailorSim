class_name RescueDialog
extends ModalPanel
## Tells the player what happened when their boat was lost at sea: rescued,
## brought back to the home harbour, the fee and what money is left. The
## rescue itself has already happened (GameSession.rescue()); this dialog
## only reports it. While it is open the game is paused (any open modal pauses
## gameplay), and closing it continues at 1× time.

const TITLE := "Rescued at Sea"

var info := {}

@onready var _title: Label = %Title
@onready var _message: Label = %Message
@onready var _details: Label = %Details


func setup(rescue_info: Dictionary) -> void:
	info = rescue_info


func _ready() -> void:
	_title.text = TITLE
	var port := PortCatalog.get_default().get_display_name(StringName(info.get("port_id", "copenhagen")))
	_message.text = (Loc.t("Your boat was too badly damaged to sail on. A maritime rescue crew took you and the %s ") +
		Loc.t("in tow and brought you both safely back to %s. The boat has been repaired and is ready to sail; ") +
		(Loc.t("your companion and supplies are aboard.") if GameSession.get_companion_count() == 1
			else Loc.t("your companions and supplies are aboard.") if GameSession.get_companion_count() > 1
			else Loc.t("your supplies are aboard."))) % [GameSession.get_vessel_definition().display_name, port]
	_details.text = Loc.t("Return destination: %s\nRescue fee: %s\nRemaining funds: %s") % [port,
		GameSession.format_money(int(info.get("fee", 0))), GameSession.format_money(int(info.get("funds_after", 0)))]
	%ContinueButton.pressed.connect(close)


func get_text() -> String:
	return "%s\n%s\n%s" % [_title.text, _message.text, _details.text]


func focus_default() -> void:
	%ContinueButton.grab_focus()
