#!/usr/bin/env python3
"""Temporary host declarations from local Bend ABI signatures.

Remove this generator after extending and adopting bend-emit:
https://github.com/dearlordylord/bendvy-ecs-examples/issues/14

Bend remains the contract owner. Compiler-only types and external ECS storage are
opaque to the host. This is not a Bend parser: unsupported ABI declarations fail
rather than weakening the TypeScript boundary.
"""
from pathlib import Path
import re
import json
import posixpath

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'examples/survivors'
OUTPUT = ROOT / '.typescript/bend.d.ts'
LOCAL_ABI_MODULES = ('offline-policy/preference.bend',)


def split(source, separator=','):
    depth = 0
    start = 0
    rows = []
    for i, char in enumerate(source):
        if char in '<({': depth += 1
        if char in '>)}' and not (char == '>' and i and source[i-1] == '-'): depth -= 1
        if char == separator and depth == 0:
            rows.append(source[start:i].strip()); start = i + 1
    if depth != 0: raise ValueError(f'unbalanced host type/signature {source!r}')
    rows.append(source[start:].strip())
    return [row for row in rows if row]


def namespace(path):
    return ''.join(part.capitalize() for component in path.parts for part in component.split('-'))


def signature_return(tail):
    """Find the body colon outside tuple/function/proof/type nesting."""
    depth = 0
    for index, char in enumerate(tail):
        if char in '(<{': depth += 1
        if char in ')}>' and not (char == '>' and index and tail[index-1] == '-'): depth -= 1
        if char == ':' and depth == 0:
            result = tail[:index].strip()
            if not result: break
            return result
    raise ValueError(f'unsupported or multiline return signature {tail!r}')


def generate(source_dir, local_modules=()):
    paths = [*source_dir.glob('*.bend'), *(source_dir / path for path in local_modules)]
    sources = {p.relative_to(source_dir).with_suffix('').as_posix(): p.read_text() for p in paths if not p.stem.endswith(('-LAWS', '-PROOF'))}
    type_names = {name: set(re.findall(r'^type\s+(\w+)', text, re.M)) for name, text in sources.items()}
    imports = {}
    for name, text in sources.items():
        imports[name] = {}
        for path, alias in re.findall(r'^import\s+(\S+)\s+as\s+(\w+)', text, re.M):
            target = posixpath.normpath(posixpath.join(posixpath.dirname(name), path)).removesuffix('.bend')
            imports[name][alias] = target if target in sources and '@' not in path else None


    def host_type(source, owner, parameters=()):
        source = source.strip().lstrip('+')
        if source.startswith('(') and source.endswith(')'):
            return host_type(source[1:-1], owner, parameters)
        # Quantities control Bend ownership and are erased from the host ABI.
        if source in parameters: return source
        if source in ('U8', 'U16', 'U32', 'U64', 'Nat', 'Int', 'F32', 'F64'): return 'number'
        if source == 'Bool': return 'boolean'
        if source == 'String': return 'string'
        if source == 'Unit': return '{ $: "Unit" }'
        if source in ('Data', 'Type'): return opaque(source, 'erased universe')
        if source.startswith('IO(') and source.endswith(')'): return opaque(source, 'compiler IO program')
        if '->' in source: return opaque(source, 'higher-order compiler template')
        if source.endswith('()'):
            parts = source[:-2].split('.')
            target = owner if len(parts) == 1 else imports[owner].get(parts[0])
            if target and parts[-1] in type_functions[target]: return opaque(source, 'computed compiler type')
            raise ValueError(f'{owner}: unknown computed host type {source!r}')
        parts = split(source, '&')
        if len(parts) > 1:
            return '{ $: "Tuple"; fst: ' + host_type(parts[0],owner,parameters) + '; snd: ' + host_type('&'.join(parts[1:]),owner,parameters) + ' }'
        match = re.fullmatch(r'([\w.]+)(?:<(.*)>)?', source)
        if not match: raise ValueError(f'{owner}: unsupported host type {source!r}')
        base, arguments = match.groups()
        args = [host_type(a,owner,parameters) for a in split(arguments or '') if not re.fullmatch(r'&[012]', a)]
        if base in ('List', 'Maybe') and len(args) != 1:
            raise ValueError(f'{owner}: {base} requires exactly one host type argument')
        if base == 'List': return 'BendList<' + (args[-1] if args else 'unknown') + '>'
        if base == 'Maybe': return 'BendMaybe<' + (args[-1] if args else 'unknown') + '>'
        if base == 'Result': return opaque(source, 'Base result representation')
        if '.' in base:
            alias, member = base.split('.',1)
            target = imports[owner].get(alias)
            if alias not in imports[owner]: raise ValueError(f'{owner}: unknown import alias {alias!r}')
            if not target: return opaque(source, 'external package storage/resource')
            if member not in type_names[target]: raise ValueError(f'{owner}: unknown imported type {source!r}')
            base = namespace(Path(target)) + '.' + member
        elif base not in type_names[owner]:
            if base in {'Char', 'Cmp', 'Audio', 'Event', 'Image', 'File', 'Array', 'Window', 'App'}:
                return opaque(source, 'Base compiler-owned resource')
            if base in function_names[owner]: return opaque(source, 'higher-order compiler template reference')
            raise ValueError(f'{owner}: unknown host type {source!r}')
        return base + ('<' + ', '.join(args) + '>' if args else '')


    def opaque(source, reason):
        opaque_categories.add((source, reason))
        return 'unknown'

    opaque_categories = set()
    function_names = {owner: set(re.findall(r'^def\s+(\w+)\(', text, re.M)) for owner, text in sources.items()}
    type_functions = {owner: set(re.findall(r'^def\s+(\w+)\([^\n]*\)\s*->\s*(?:Type|Data)\s*:', text, re.M)) for owner, text in sources.items()}

    wire_schema = {}
    def wire_type(source, owner):
        source = source.strip().lstrip('+')
        primitive = {'U32': 'u32', 'F32': 'f32', 'F64': 'f64', 'Nat': 'nat', 'Bool': 'bool', 'String': 'string'}
        if source in primitive: return primitive[source]
        resolved = host_type(source, owner)
        for base, key in [('List', 'list'), ('Maybe', 'maybe')]:
            if source.startswith(base + '<'):
                args = [a for a in split(source[len(base)+1:-1]) if not re.fullmatch(r'&[012]', a)]
                return {key: wire_type(args[0], owner)}
        if resolved == 'unknown' or '<' in resolved or resolved == 'number': return None
        return {'ref': resolved if '.' in resolved else namespace(Path(owner)) + '.' + resolved}

    output = ['// Generated by scripts/generate-bend-types.py. Do not edit.',
              'type BendList<T> = { $: "Nil" } | { $: "Con"; head: T; tail: BendList<T> };',
              'type BendMaybe<T> = { $: "None" } | { $: "Some"; value: T };',
              'type Prefix<P extends string, T> = {[K in keyof T as K extends string ? `${P}:${K}` : never]: T[K]};',
              'declare namespace BendABI {']
    for owner, text in sorted(sources.items()):
        output.append(f'  namespace {namespace(Path(owner))} {{')
        # Every declaration must be consumed, including unsupported syntax.
        type_matches = list(re.finditer(r'^type\s+(\w+)(?:<([^\n]*?)>)?\s+is\s+(?:Data|Type):\s*([^\n]*(?:\n[ \t]+[^\n]*)*)', text, re.M))
        if len(type_matches) != len(re.findall(r'^type\b', text, re.M)):
            raise ValueError(f'{owner}: unsupported type declaration')
        for match in type_matches:
            name, generics, body = match.groups()
            parameters = re.findall(r'[-+]?([A-Za-z]\w*)\s*:', generics or '')
            if generics and any(not re.fullmatch(r'[-+]?[A-Za-z]\w*\s*:\s*(?:Data|Type)', part) for part in split(generics)):
                raise ValueError(f'{owner}.{name}: unsupported type parameters {generics!r}')
            variants = []
            wire_variants = []
            constructors = list(re.finditer(r'(\w+)\s*\{([^{}]*)\}', body))
            remainder = re.sub(r'(\w+)\s*\{([^{}]*)\}', '', body)
            remainder = re.sub(r'#.*', '', remainder).strip()
            if remainder: raise ValueError(f'{owner}.{name}: unsupported constructor syntax {remainder!r}')
            for constructor_match in constructors:
                constructor, fields = constructor_match.groups()
                members = [f'$: "{constructor}"']
                wire_fields = []
                for field in split(fields):
                    field_name, field_type = field.split(':',1)
                    members.append(field_name.strip() + ': ' + host_type(field_type,owner,parameters))
                    if not parameters: wire_fields.append([field_name.strip(), wire_type(field_type, owner)])
                variants.append('{ ' + '; '.join(members) + ' }')
                wire_variants.append([constructor, wire_fields])
            if not parameters: wire_schema[namespace(Path(owner)) + '.' + name] = wire_variants
            if not variants: raise ValueError(f'{owner}.{name}: missing constructor')
            generic_text = '<' + ', '.join(p+' = unknown' for p in parameters) + '>' if parameters else ''
            output.append(f'    type {name}{generic_text} = ' + ' | '.join(variants) + ';')
        parents = ', '.join(f'Prefix<"{target}", {namespace(Path(target))}.API>' for target in dict.fromkeys(imports[owner].values()) if target)
        output.append('    interface API' + (' extends ' + parents if parents else '') + ' {')
        for line in text.splitlines():
            if not re.match(r'^def\b', line): continue
            match = re.match(r'def\s+(\w+)\(', line)
            if not match:
                proof = re.match(r'def\s+(\w+)\.\w+\(', line)
                if proof and re.search(r'^import\s+\S+-[Ll][Aa][Ww][Ss]\.bend\s+as\s+' + re.escape(proof[1]) + r'\s*$', text, re.M):
                    opaque(proof[1], 'erased qualified law proof')
                    continue
                raise ValueError(f'{owner}: unsupported definition {line!r}')
            name = match[1]
            depth = 1
            end = match.end()
            while depth:
                if end >= len(line): raise ValueError(f'{owner}.{name}: unsupported multiline signature')
                if line[end] == '(': depth += 1
                if line[end] == ')': depth -= 1
                end += 1
            inputs = line[match.end():end-1]
            tail = line[end:].strip()
            if not tail.startswith('->'): raise ValueError(f'{owner}.{name}: missing explicit return type')
            tail = tail[2:].strip()
            returns = signature_return(tail)
            if returns in ('Type','Data') or returns.startswith('{'):
                opaque(returns, 'erased proof/type export')
                continue
            args=[];params=[]
            for index, field in enumerate(split(inputs)):
                if ':' not in field: raise ValueError(f'{owner}.{name}: unsupported parameter {field}')
                key,typ=field.split(':',1); key=key.strip()
                if key.startswith('~'):
                    if typ.strip() in ('Data','Type'):params.append(key[1:])
                    opaque(typ.strip(), 'erased template parameter')
                    continue
                key=key.lstrip('+&0123456789 ')
                args.append('arg_'+(key if key!='_' else str(index))+': '+host_type(typ,owner,params))
            generic_text='<'+', '.join(p+' = unknown' for p in params)+'>' if params else ''
            output.append(f'      {name}{generic_text}('+', '.join(args)+'): '+host_type(returns,owner,params)+';')
        output.extend(['    }','  }'])
    output.append('}')
    for owner in sorted(sources):
        output.extend([f'declare module "*dist/{owner}.mjs" {{',f'  const api: BendABI.{namespace(Path(owner))}.API;', '  export default api;', '}'])
    output.extend('// Opaque ABI: ' + reason + ': ' + typ for typ, reason in sorted(opaque_categories))
    reachable = {}
    pending = ['CoopNetwork.Snapshot']
    def visit(spec):
        if spec is None: raise ValueError('unsupported type in network contract')
        if isinstance(spec, dict):
            if 'ref' in spec: pending.append(spec['ref'])
            else:
                for child in spec.values(): visit(child)
    while pending:
        name = pending.pop()
        if name in reachable: continue
        variants = wire_schema[name]
        reachable[name] = variants
        for _, fields in variants:
            for _, spec in fields: visit(spec)
    schema_output = ROOT / 'examples/survivors/network-schema.generated.mts'
    schema_output.write_text('// Generated by scripts/generate-bend-types.py. Do not edit.\n'
        + 'import type { WireSchema } from "./network-schema.mts"\n'
        + 'export const networkSchema = ' + json.dumps(reachable, indent=2) + ' as const satisfies WireSchema\n')
    return '\n'.join(output)+'\n'

if __name__ == '__main__':
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(generate(SOURCE, LOCAL_ABI_MODULES))
    print(f'Bend host declarations: {OUTPUT.relative_to(ROOT)}')
