extends SceneTree

var _failures: Array[String] = []


func _find_visible_button(root_node: Node, expected_text: String) -> Button:
	if root_node == null:
		return null
	for node in root_node.find_children("*", "Button", true, false):
		if node is Button and node.is_visible_in_tree() and node.text == expected_text:
			return node
	return null


func _find_visible_label_containing(root_node: Node, fragment: String) -> Label:
	if root_node == null:
		return null
	for node in root_node.find_children("*", "Label", true, false):
		if node is Label and node.is_visible_in_tree() and node.text.contains(fragment):
			return node
	return null


func _find_visible_label_exact(root_node: Node, expected_text: String) -> Label:
	if root_node == null:
		return null
	for node in root_node.find_children("*", "Label", true, false):
		if node is Label and node.is_visible_in_tree() and node.text == expected_text:
			return node
	return null


func _ancestor_panel(node: Node, boundary: Node) -> PanelContainer:
	var current := node
	while current != null and current != boundary:
		if current is PanelContainer:
			return current
		current = current.get_parent()
	return null


func _expect(condition: bool, context: String) -> void:
	if not condition:
		_failures.append(context)


func _expect_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		_failures.append("%s：期望 %s，实际 %s" % [context, expected, actual])
