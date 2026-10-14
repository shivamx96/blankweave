import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
SHELL=Path(__file__).resolve().parents[1]/'defaults/shell';sys.path.insert(0,str(SHELL))
class System(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        env=patch.dict(os.environ,XDG_CONFIG_HOME=str(self.root/'config'),XDG_STATE_HOME=str(self.root/'state'));env.start();self.addCleanup(env.stop)
        spec=importlib.util.spec_from_file_location('system',SHELL/'system-settings.py');self.m=importlib.util.module_from_spec(spec);spec.loader.exec_module(self.m)
        self.m.COMMAND=self.root/'blankweave';self.m.COMMAND.write_text('#!/bin/sh\nprintf "FAIL check\\n"\nexit 1\n');self.m.COMMAND.chmod(0o700)
    def apply(self):self.m.apply(dict(revision=self.m.status()['revision'],action='diagnose'))
    def test_nonzero_findings_are_saved_and_command_is_readonly(self):
        with patch.object(self.m.subprocess,'run',return_value=subprocess.CompletedProcess([],1,'FAIL test\n','')) as command:
            self.apply();self.assertEqual(command.call_args.args[0],[str(self.m.COMMAND),'doctor','--normal','--report'])
        report=self.m.status()['report'];self.assertEqual(report['code'],1);self.assertIn('FAIL',report['text'])
        self.assertEqual(self.m.REPORT.stat().st_mode & 0o777,0o600)
    def test_read_does_not_run_doctor_and_timeout_preserves_report(self):
        with patch.object(self.m.subprocess,'run',side_effect=AssertionError('Must be explicit')):self.m.status()
        self.apply();old=self.m.REPORT.read_bytes()
        with patch.object(self.m.subprocess,'run',side_effect=subprocess.TimeoutExpired('doctor',90)):
            with self.assertRaises(subprocess.TimeoutExpired):self.apply()
        self.assertEqual(self.m.REPORT.read_bytes(),old)
    def test_stale_symlink_and_missing_cli(self):
        stale=self.m.status()['revision'];self.apply()
        with self.assertRaises(ValueError):self.m.apply(dict(revision=stale,action='diagnose'))
        target=self.root/'report';target.write_bytes(self.m.REPORT.read_bytes());self.m.REPORT.unlink();self.m.REPORT.symlink_to(target)
        self.assertFalse(self.m.status()['writable'])
        with self.assertRaises(ValueError):self.apply()
        self.m.COMMAND.unlink();self.assertFalse(self.m.status()['available'])
if __name__=='__main__':unittest.main()
