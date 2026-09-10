"""Execute this module's actual Story rules against a small deterministic API model.

This checks rule logic, not BG3 engine behavior. Both immediate and deferred status
callbacks are tested; actual native passive/status timing remains a gameplay test.
"""
import copy
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / 'src/Mods/ExplorationBenefitsStory/Story/RawFiles/Goals/EBS_Exploration.txt'


def atom(text):
    text = re.sub(r'\((?:CHARACTER|GUIDSTRING|INTEGER|STRING)\)', '', text.strip())
    if text.startswith('"'):
        return text[1:-1]
    if re.fullmatch(r'-?\d+(?:\.\d+)?', text):
        return float(text) if '.' in text else int(text)
    return text


def call(text):
    match = re.fullmatch(r'(\w+)\((.*)\);?', text.strip())
    if not match:
        raise AssertionError(f'Unsupported call: {text}')
    return match[1], [atom(x) for x in match[2].split(',')] if match[2] else []


def variable(value):
    return isinstance(value, str) and value.startswith('_')


def bind(pattern, values, env):
    result = dict(env)
    for p, value in zip(pattern, values, strict=True):
        if p == '_':
            continue
        if variable(p) and p not in result:
            result[p] = value
        elif result.get(p, p) != value:
            return None
    return result


class Story:
    def __init__(self, deferred=False):
        self.rules = []
        self.db = {'DB_Players': set()}
        self.people = {}
        self.queue = []
        self.deferred = deferred
        self.applies = 0
        text = SOURCE.read_text(encoding='utf-8')
        for block in re.split(r'(?m)(?=^(?:PROC|IF)$)', text)[1:]:
            lines = [line.strip() for line in block.splitlines() if line.strip()]
            end = next((i for i, x in enumerate(lines) if x == 'EXITSECTION'), len(lines))
            lines = lines[:end]
            split = lines.index('THEN')
            self.rules.append((lines[0], call(lines[1]), [x for x in lines[2:split] if x != 'AND'], lines[split + 1:]))

    def add_person(self, name, *, member=True, player=True, summon=False, combat=False, region='WLD'):
        self.people[name] = dict(member=member, player=player, summon=summon, combat=combat,
                                 dead=False, region=region, passive=False, toggle=False, statuses=set())
        if member:
            self.db['DB_Players'].add((name,))

    def condition(self, text, env):
        if ' != ' in text:
            a, b = map(atom, text.split(' != '))
            return [env] if env.get(a, a) != env.get(b, b) else []
        negative = text.startswith('NOT ')
        name, args = call(text[4:] if negative else text)
        resolved = [env.get(a, a) for a in args]
        if name.startswith('DB_'):
            rows = list(self.db.get(name, set()))
        else:
            subject = self.people.get(resolved[0])
            keys = {'IsPlayer': 'player', 'IsSummon': 'summon', 'IsInCombat': 'combat', 'IsDead': 'dead'}
            if name in keys:
                rows = [(resolved[0], int(subject[keys[name]]))]
            elif name == 'IsPartyMember':
                rows = [(resolved[0], resolved[1], int(subject['member']))]
            elif name == 'GetRegion':
                rows = [(resolved[0], subject['region'])]
            elif name == 'IsCharacterCreationLevel':
                rows = [(resolved[0], int(resolved[0] == 'SYS_CC_I'))]
            elif name == 'HasPassive':
                rows = [(resolved[0], resolved[1], int(subject['passive']))]
            elif name == 'HasActiveStatus':
                rows = [(resolved[0], resolved[1], int(resolved[1] in subject['statuses']))]
            else:
                raise AssertionError(f'Unsupported query: {name}')
        results = [bound for row in rows if (bound := bind(args, row, env)) is not None]
        return ([env] if not results else []) if negative else results

    def invoke(self, kind, name, values):
        for rule_kind, (rule_name, args), conditions, actions in self.rules:
            if (rule_kind, rule_name) != (kind, name):
                continue
            env = bind(args, values, {})
            if env is None:
                continue
            environments = [env]
            for condition in conditions:
                environments = [result for e in environments for result in self.condition(condition, e)]
            for e in environments:
                for action in actions:
                    self.action(action, e)

    def status(self, character, status, on):
        statuses = self.people[character]['statuses']
        if (status in statuses) == on:
            return
        (statuses.add if on else statuses.remove)(status)
        event = ('StatusApplied' if on else 'StatusRemoved', [character, status, character, 0])
        if self.deferred:
            self.queue.append(event)
        else:
            self.invoke('IF', *event)

    def toggle(self, character):
        person = self.people[character]
        person['toggle'] = not person['toggle']
        self.status(character, 'EBS_ENABLED', person['toggle'])
        if not person['toggle']:
            self.status(character, 'EBS_EXPLORING', False)

    def action(self, text, env):
        negative = text.startswith('NOT ')
        name, args = call(text[4:] if negative else text)
        values = tuple(env.get(a, a) for a in args)
        if name.startswith('DB_'):
            rows = self.db.setdefault(name, set())
            (rows.discard if negative else rows.add)(values)
        elif name.startswith('PROC_'):
            self.invoke('PROC', name, values)
        elif name == 'AddPassive':
            self.people[values[0]]['passive'] = True
            self.people[values[0]]['toggle'] = False
            self.toggle(values[0])
        elif name == 'RemovePassive':
            self.people[values[0]]['passive'] = False
            self.people[values[0]]['toggle'] = False
            self.status(values[0], 'EBS_ENABLED', False)
        elif name == 'TogglePassive':
            self.toggle(values[0])
        elif name in ('ApplyStatus', 'RemoveStatus'):
            self.applies += name == 'ApplyStatus'
            self.status(values[0], values[1], name == 'ApplyStatus')
        else:
            raise AssertionError(f'Unsupported action: {name}')

    def drain(self):
        limit = 100
        while self.queue:
            limit -= 1
            assert limit > 0, 'Event loop did not settle'
            self.invoke('IF', *self.queue.pop(0))

    def event(self, name, *args):
        self.invoke('IF', name, args)
        self.drain()


class ExplorationRules(unittest.TestCase):
    def check(self, story, who, on):
        self.assertEqual('EBS_EXPLORING' in story.people[who]['statuses'], on)

    def test_actual_source_lifecycle(self):
        for deferred in (False, True):
            with self.subTest(deferred_callbacks=deferred):
                s = Story(deferred)
                s.add_person('a')
                s.add_person('b')
                s.add_person('summon', summon=True)
                s.add_person('stranger', player=False, member=False)
                s.add_person('dummy', region='SYS_CC_I')
                s.event('LevelGameplayStarted', 'WLD', 0)
                for who in ('a', 'b'):
                    self.check(s, who, True)
                    self.assertTrue(s.people[who]['toggle'])
                for who in ('summon', 'stranger', 'dummy'):
                    self.assertFalse(s.people[who]['passive'])
                # Native effects must survive all cleanup.
                s.people['a']['statuses'].update({'LONG_JUMP', 'PETPAL', 'FEATHER_FALL'})
                s.people['a']['combat'] = True
                s.event('EnteredCombat', 'a', 'combat-1')
                self.check(s, 'a', False)
                self.check(s, 'b', True)
                self.assertTrue(s.people['a']['toggle'])
                s.event('LevelGameplayStarted', 'WLD', 0)
                self.check(s, 'a', False)
                s.people['a']['combat'] = False
                s.event('LeftCombat', 'a', 'combat-1')
                self.check(s, 'a', True)
                s.toggle('a')
                s.drain()
                self.check(s, 'a', False)
                self.assertIn(('a', 0), s.db['DB_EBS_Enabled'])
                s.people['a']['combat'] = True
                s.event('EnteredCombat', 'a', 'combat-2')
                s.people['a']['combat'] = False
                s.event('LeftCombat', 'a', 'combat-2')
                self.check(s, 'a', False)
                # Reload with persisted database and native character state.
                saved = copy.deepcopy((s.db, s.people))
                s = Story(deferred)
                s.db, s.people = saved
                s.event('LevelGameplayStarted', 'WLD', 0)
                self.check(s, 'a', False)
                self.assertFalse(s.people['a']['toggle'])
                self.check(s, 'b', True)
                s.event('LongRestFinished')
                self.check(s, 'a', False)
                # Regrant after respec must project saved OFF instead of default ON.
                s.people['a']['passive'] = False
                s.event('RespecCompleted', 'a')
                self.check(s, 'a', False)
                self.assertFalse(s.people['a']['toggle'])
                s.people['a']['member'] = False
                s.event('CharacterLeftParty', 'a')
                self.assertFalse(s.people['a']['passive'])
                s.people['a']['member'] = True
                s.event('CharacterJoinedParty', 'a')
                self.check(s, 'a', False)
                self.assertFalse(s.people['a']['toggle'])
                s.people['a']['combat'] = True
                s.toggle('a')
                s.drain()
                self.check(s, 'a', False)
                self.assertIn(('a', 1), s.db['DB_EBS_Enabled'])
                s.people['a']['combat'] = False
                s.event('LeftCombat', 'a', 'combat-3')
                self.check(s, 'a', True)
                s.people['a']['dead'] = True
                s.event('Died', 'a')
                self.check(s, 'a', False)
                s.people['a']['dead'] = False
                s.event('Resurrected', 'a')
                self.check(s, 'a', True)
                applies = s.applies
                s.event('GainedControl', 'a')
                self.assertEqual(s.applies, applies, 'No repeat status stacking')
                self.assertTrue({'LONG_JUMP', 'PETPAL', 'FEATHER_FALL'} <= s.people['a']['statuses'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
