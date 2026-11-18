class_name HelpPageDef
extends Resource
## One page of the F1 help screen (ticket 85, D59c). Data only: HelpScreen shows it. The body is plain text with blank
## lines between paragraphs; a {token} in it is replaced from data when the page is shown (HelpScreen.resolve), so a
## number the page cites is never typed in. `keys` lists the key names (KEY_<name> in Godot) the Controls page
## mentions; a test checks each one is bound in code.

@export var id: String = ""
@export var order: int = 1
@export var title: String = ""
@export_multiline var body: String = ""
@export var keys: PackedStringArray = PackedStringArray()
