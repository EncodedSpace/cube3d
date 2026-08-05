@tool
extends Node3D

@export var n:int = 8
@export var wall_color:Color = Color(0.5, 0.5, 0.55)
@export var path_color:Color = Color.RED
@export var path_radius:float = 0.12
@export var start_color:Color = Color.GREEN
@export var end_color:Color = Color.BLUE

@export_tool_button("Generate Map")
var generate_map := func(): _generate_from_editor()

@export_tool_button("Clear Map", "Callable")
var clear_map_button := func(): _clear_from_editor()
func _clear_from_editor():
	if Engine.is_editor_hint():
		_clear_children()
		matrix.clear()
		path.clear()
		
var rng := RandomNumberGenerator.new()

var matrix:Array = []
var start_pos:Vector3i
var end_pos:Vector3i
var path:Array[Vector3i] = []
var _last_visited:Dictionary = {}

func _ready():
	rng.randomize()

	if Engine.is_editor_hint():
		return

	generate()

func _generate_from_editor():
	if Engine.is_editor_hint():
		generate()

func generate():
	_clear_children()

	var success := false

	for i in range(300):
		# Order matters: pick start/end first, then generate blocks around them.
		_init_matrix()
		if !_pick_start_end():
			continue
		_generate_surface()
		path = _find_path_with_retry()

		if path.is_empty():
			continue

		if _count_path_faces(path) >= 4:
			success = true
			break

	if !success:
		push_error("Cannot generate a path across at least 4 faces.")
		return
	_build_walls()
	_build_path()
	_build_markers()
	_build_camera_and_light()
func _get_faces(p:Vector3i)->Array[String]:
	var faces:Array[String]=[]

	if p.x==0:
		faces.append("Left")
	elif p.x==n-1:
		faces.append("Right")

	if p.y==0:
		faces.append("Bottom")
	elif p.y==n-1:
		faces.append("Top")

	if p.z==0:
		faces.append("Back")
	elif p.z==n-1:
		faces.append("Front")

	return faces
	
func _count_path_faces(p:Array[Vector3i])->int:
	var used := {}

	for cell in p:
		for face in _get_faces(cell):
			used[face] = true

	return used.size()
	
	
func _init_matrix():
	matrix.clear()
	for x in range(n):
		var p:Array=[]
		for y in range(n):
			var r:Array=[]
			for z in range(n):
				r.append(0)
			p.append(r)
		matrix.append(p)

func _generate_surface():
	for x in range(n):
		for y in range(n):
			for z in range(n):
				if not _is_on_surface(x,y,z):
					continue
				# Never place a solid block on start or end position.
				var p := Vector3i(x, y, z)
				if p == start_pos or p == end_pos:
					matrix[x][y][z] = 0
				else:
					matrix[x][y][z] = rng.randi_range(0, 1)

func _is_on_surface(x:int,y:int,z:int)->bool:
	return x==0 or x==n-1 or y==0 or y==n-1 or z==0 or z==n-1

func _pick_start_end()->bool:
	# Called before _generate_surface, so the matrix is all zeros here.
	# Pick start/end from all surface cells; _generate_surface will keep
	# those two cells clear when scattering solid blocks.
	var cells:Array[Vector3i]=[]
	for x in range(n):
		for y in range(n):
			for z in range(n):
				if _is_on_surface(x,y,z):
					cells.append(Vector3i(x,y,z))
	if cells.size()<2:
		return false
	# Prefer start positions on the bottom face (y == 0) so the player
	# spawns on the floor and we avoid rotating the whole cube.
	var bottom_cells:Array[Vector3i] = []
	for r in cells:
		if r.y == 0:
			bottom_cells.append(r)
	if not bottom_cells.is_empty():
		start_pos = bottom_cells[rng.randi_range(0, bottom_cells.size() - 1)]
	else:
		start_pos = cells[rng.randi_range(0, cells.size() - 1)]
	var cand:Array[Vector3i]=[]
	for c in cells:
		if c!=start_pos and max(abs(c.x-start_pos.x),max(abs(c.y-start_pos.y),abs(c.z-start_pos.z)))>2:
			cand.append(c)
	if cand.is_empty():
		cand=cells.duplicate()
		cand.erase(start_pos)
	end_pos=cand[rng.randi_range(0,cand.size()-1)]
	return true

func _neighbors(p:Vector3i)->Array[Vector3i]:
	var out:Array[Vector3i]=[]
	for d: Vector3i in [Vector3i.RIGHT,Vector3i.LEFT,Vector3i.UP,Vector3i.DOWN,Vector3i(0,0,1),Vector3i(0,0,-1)]:
		var q: Vector3i = p+d
		if q.x>=0 and q.y>=0 and q.z>=0 and q.x<n and q.y<n and q.z<n:
			if _is_on_surface(q.x,q.y,q.z) and matrix[q.x][q.y][q.z]==0:
				out.append(q)
	return out

func _find_path_with_retry()->Array[Vector3i]:
	for i in range(5000):
		var p=_bfs()
		if !p.is_empty():
			return p
		_remove_wall()
	return []

func _bfs()->Array[Vector3i]:
	var q:Array[Vector3i]=[start_pos]
	var head:=0
	var vis:Dictionary={}
	var par:Dictionary={}
	vis[start_pos]=true
	while head<q.size():
		var c: Vector3i = q[head]; head+=1
		if c==end_pos:
			var r:Array[Vector3i]=[c]
			while par.has(c):
				c=par[c]
				r.push_front(c)
			return r
		for nb: Vector3i in _neighbors(c):
			if !vis.has(nb):
				vis[nb]=true
				par[nb]=c
				q.append(nb)
	_last_visited=vis
	return []

func _remove_wall():
	var list:Array[Vector3i]=[]
	for k in _last_visited.keys():
		var c: Vector3i = k
		for d: Vector3i in [Vector3i.RIGHT,Vector3i.LEFT,Vector3i.UP,Vector3i.DOWN,Vector3i(0,0,1),Vector3i(0,0,-1)]:
			var q: Vector3i = c+d
			if q.x>=0 and q.y>=0 and q.z>=0 and q.x<n and q.y<n and q.z<n:
				if _is_on_surface(q.x,q.y,q.z) and matrix[q.x][q.y][q.z]==1 and !list.has(q):
					list.append(q)
	if list.is_empty(): return
	var w=list[rng.randi_range(0,list.size()-1)]
	matrix[w.x][w.y][w.z]=0

func _wp(x:int,y:int,z:int)->Vector3:
	var o = -(n - 1) / 2.0
	# Block centers sit 0.5 above the integer y so boxes align with runtime generator.
	return Vector3(x + o, float(y) + 0.5, z + o)

func _build_walls():
	var mesh:=BoxMesh.new()
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=wall_color
	for x in range(n):
		for y in range(n):
			for z in range(n):
				if matrix[x][y][z]==1:
					var m:=MeshInstance3D.new()
					m.mesh=mesh
					m.material_override=mat
					m.position=_wp(x,y,z)
					add_child(m)
					if Engine.is_editor_hint():
						m.owner = owner

func _build_path():
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=path_color
	for i in range(path.size()-1):
		var a=_wp(path[i].x,path[i].y,path[i].z)
		var b=_wp(path[i+1].x,path[i+1].y,path[i+1].z)
		var c:=MeshInstance3D.new()
		var cy:=CylinderMesh.new()
		cy.top_radius=path_radius
		cy.bottom_radius=path_radius
		cy.height=a.distance_to(b)
		c.mesh=cy
		c.material_override=mat
		
		# 先加入场景树，保证 look_at 生效
		add_child(c)
		if Engine.is_editor_hint():
			c.owner = owner
			
		c.position=(a+b)/2.0
		
		# 防止 Target Vector 与 Up Vector 共线产生 Warning
		var dir := (b - a).normalized()
		var up_vec := Vector3.UP
		if abs(dir.dot(Vector3.UP)) > 0.99:
			up_vec = Vector3.FORWARD
			
		c.look_at(b, up_vec)
		c.rotate_object_local(Vector3.RIGHT, PI/2)

func _build_markers():
	for pair in [[start_pos,start_color],[end_pos,end_color]]:
		var s:=MeshInstance3D.new()
		var sm:=SphereMesh.new()
		sm.radius=0.35
		s.mesh=sm
		var m:=StandardMaterial3D.new()
		m.albedo_color=pair[1]
		s.material_override=m
		var p:Vector3i=pair[0]
		s.position=_wp(p.x,p.y,p.z)
		add_child(s)
		if Engine.is_editor_hint():
			s.owner = owner

func _build_camera_and_light():
	var l:=DirectionalLight3D.new()
	l.rotation=Vector3(-PI/4,PI/4,0)
	add_child(l)
	if Engine.is_editor_hint():
		l.owner = owner
		
	var cam:=Camera3D.new()
	var d=n*1.2
	cam.position=Vector3(d,d*0.7,d)
	
	# 先 add_child 再 look_at，消除 "Node not inside tree" 错误
	add_child(cam)
	if Engine.is_editor_hint():
		cam.owner = owner
	cam.look_at(Vector3.ZERO)
	# Ensure the generated camera becomes active so viewport uses it immediately.
	cam.current = true

func _clear_children():
	for c in get_children():
		if Engine.is_editor_hint():
			remove_child(c)
			c.free()
		else:
			c.queue_free()
