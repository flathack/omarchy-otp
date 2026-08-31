from __future__ import annotations

import json
import unittest
from pathlib import Path


PANEL = (Path(__file__).resolve().parents[1] / "Panel.qml").read_text(encoding="utf-8")
MANIFEST = json.loads(
    (Path(__file__).resolve().parents[1] / "manifest.json").read_text(encoding="utf-8")
)


class PanelContractTests(unittest.TestCase):
    def test_public_plugin_namespace_is_consistent(self) -> None:
        self.assertEqual(MANIFEST["id"], "flathack.otp")
        self.assertEqual(MANIFEST["author"], "flathack")
        self.assertIn('moduleName: "flathack.otp"', PANEL)
        self.assertIn('ipcTarget: "flathack.otp"', PANEL)

    def test_filter_forwards_regular_text_input(self) -> None:
        self.assertIn("event.accepted = false", PANEL)
        self.assertIn("root.filterText = text", PANEL)

    def test_keyboard_selection_keeps_list_item_visible(self) -> None:
        self.assertIn("ListView.Contain", PANEL)
        self.assertIn("onSelectedIndexChanged: Qt.callLater(root.revealSelection)", PANEL)

    def test_delete_requires_confirmation(self) -> None:
        self.assertIn("event.key === Qt.Key_Delete", PANEL)
        self.assertIn("root.requestDeleteSelected()", PANEL)
        self.assertIn("ConfirmDialog {", PANEL)
        self.assertIn("onConfirmed: root.confirmDelete()", PANEL)

    def test_copy_and_delete_use_stable_account_ids(self) -> None:
        self.assertIn('String(entry.account.id)', PANEL)
        self.assertIn('id: String(account.id)', PANEL)
        self.assertNotIn('String(entry.account.index)', PANEL)
        self.assertNotIn('index: Number(account.index)', PANEL)

    def test_copy_and_delete_report_success(self) -> None:
        self.assertIn('root.actionStatus = "COPIED"', PANEL)
        self.assertIn('root.actionStatus = "DELETED"', PANEL)

    def test_external_text_is_rendered_as_plain_text(self) -> None:
        for binding in (
            "text: root.errorText",
            "text: accountRow.modelData.account.name",
            'text: accountRow.modelData.account.issuer || ""',
        ):
            start = PANEL.index(binding)
            text_block = PANEL[start : PANEL.index("}", start)]
            self.assertIn("textFormat: Text.PlainText", text_block)


if __name__ == "__main__":
    unittest.main()
