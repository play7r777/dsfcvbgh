import re

def halve_match(match):
    val = float(match.group(0))
    if val.is_integer():
        return str(int(val // 2))
    return str(val / 2)

with open('src/server/Map/MapBuilder.luau', 'r', encoding='utf-8') as f:
    content = f.read()

def process_block(start_marker, end_marker, content):
    start = content.find(start_marker)
    if start == -1: return content
    end = content.find(end_marker, start)
    if end == -1: return content
    
    block = content[start:end]
    
    def repl(m):
        return re.sub(r'-?\d+', halve_match, m.group(0))
    
    block = re.sub(r'point\([^)]+\)', repl, block)
    block = re.sub(r'Vector3\.new\([^)]+\)', repl, block)
    block = re.sub(r'Vector2\.new\([^)]+\)', repl, block)
    block = re.sub(r'CFrame\.new\([^)]+\)', repl, block)
    
    return content[:start] + block + content[end:]


content = process_block('local SPAWN_POINTS = {', '}', content)
content = process_block('local TANK_PADS = {', '}', content)
content = process_block('local BIKE_PADS = {', '}', content)
content = process_block('local CONTAINER_SPAWNS = {', '}', content)
content = process_block('local VEHICLE_ROADS = {', '}', content)
content = process_block('local FOOT_PATHS = {', '}', content)
content = process_block('local TERRAIN_RISES = {', '}', content)

content = re.sub(r'local FRONT_X = 270', 'local FRONT_X = 135', content)
content = re.sub(r'local FRONT_Z = 520', 'local FRONT_Z = 260', content)

with open('src/server/Map/MapBuilder.luau', 'w', encoding='utf-8') as f:
    f.write(content)
