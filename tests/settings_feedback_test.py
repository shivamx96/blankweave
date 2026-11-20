#!/usr/bin/env python3
"""Pure error presentation tests: no desktop commands or host writes."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'defaults/shell'))
from settings_support import SettingsError, error_result, safe_detail
from settings_operations import require

class Feedback(unittest.TestCase):
    def test_common_failures(self):
        for raw, expected in [('NetworkManager is not running', 'Could not reach NetworkManager.'),
                              ('Access point not found', 'That network is no longer in range.'),
                              ('Authentication failed', 'The password was not accepted.')]:
            with self.subTest(raw=raw): self.assertEqual(error_result(ValueError(raw))['message'], expected)

    def test_unknown_has_neutral_sentence_and_separate_detail(self):
        result = error_result(RuntimeError('unknown native failure'))
        self.assertEqual(result['message'], 'Could not apply this change. Try again.')
        self.assertEqual(result['detail'], 'unknown native failure')

    def test_cancellation_is_quiet(self):
        result = error_result(ValueError('Authorization was cancelled.'))
        self.assertTrue(result['cancelled'])
        self.assertEqual(result['message'], 'Cancelled')
        self.assertEqual(result['detail'], '')

    def test_label_and_field(self):
        with self.assertRaises(SettingsError) as failure: require({}, 'uri')
        result = error_result(failure.exception)
        self.assertEqual(result['message'], 'Enter a valid server address.')
        self.assertEqual(result['field'], 'uri')

    def test_redaction(self):
        result = error_result(ValueError('bad /home/person/private/file password=hello token=abc unexpected-value'), ['unexpected-value'])
        for value in result.values():
            self.assertNotIn('/home/person', value)
            self.assertNotIn('hello', value)
            self.assertNotIn('abc', value)
            self.assertNotIn('unexpected-value', value)
        self.assertNotIn('Traceback', safe_detail('Traceback (most recent call last):\n  file x\nValueError: rejected'))

    def test_timeout(self):
        self.assertEqual(error_result(subprocess.TimeoutExpired('unused', 2))['message'], 'The service took too long to respond. Try again.')

if __name__ == '__main__': unittest.main()
