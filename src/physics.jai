
Rigid_Body :: struct {
    inverse_mass: float;

    inverse_inertia_tensor: Matrix3; // body-space
    world_inertia_tensor: Matrix3;
    orientation: Matrix3;
    angular_momentum: Vector3;
    angular_velocity: Vector3;
    torque: Vector3;

    elasticity: float = 0.3;

    is_static: bool;

    velocity: Vector3;
    force: Vector3;

    // @Incomplete do the polymorphic thing
    user_data: *Actor;

    shape_type: Type;
    shape: void;

    #place shape; // it's imperitive that this is placed at shape for the centers of the colliders to update magically
    position: Vector3;    

    #place shape;
    sphere: Sphere;

    #place shape;
    capsule: Capsule;

    #place shape;
    aabb: AABB;
}

Rigid_Body_con :: (using rb: *Rigid_Body, mass: float, sh: $Shape_Type, data: *Actor = null) {
    shape_type = Shape_Type;
    
    // infinite mass
    if mass == 0 inverse_mass = 0;
    else inverse_mass = 1.0 / mass;
    
    inverse_inertia_tensor = transpose(moment_of_inertia(sh, <<rb));
    orientation = matrix_orientation(0, 0, 1, 0);
    <<(cast(*Shape_Type) *shape) = sh;

    world_inertia_tensor = orientation * inverse_inertia_tensor * transpose(orientation);
    angular_velocity = world_inertia_tensor * angular_momentum;

    user_data = data;
    if user_data user_data.body = rb;
}

integrate :: (using rb: *Rigid_Body, dt: float) {
    if rb.is_static return;
    {
        acceleration := force * inverse_mass * dt;
        position += (0.5 * acceleration * dt) + velocity * dt;
        velocity += acceleration;
    }

    {
        // @Speed it's probably faster to multiply dt to angular_velocity
        // before we make it a skew symmetric matrix
        orientation += dt * (~angular_velocity) * orientation;
        angular_momentum += dt * torque;

        orthonormalize(*orientation);
        
        world_inertia_tensor += orientation * inverse_inertia_tensor * transpose(orientation);
        angular_velocity += world_inertia_tensor * angular_momentum;
    }
}

correct_position :: (rb0: *Rigid_Body, rb1: *Rigid_Body, cp: Contact_Point) {
    PERCENT :: 0.2;
    SLOP :: 0.001;
    correction := max(0.0, cp.dist - SLOP) / (rb0.inverse_mass + rb1.inverse_mass) * PERCENT * cp.normal;
    rb0.position += rb0.inverse_mass * correction;
    rb1.position -= rb1.inverse_mass * correction;
}

impulse_response :: (rb0: *Rigid_Body, rb1: *Rigid_Body, cp: Contact_Point) {
    d1 := (rb0.inverse_mass + rb1.inverse_mass);
    if d1 == 0 return; // two infinite mass objects!

    cr := clamp(rb0.elasticity * rb1.elasticity, 0.0, 1.0);
    rv := rb1.velocity - rb0.velocity;
    n := cp.normal;
    // r_a := cp.point_on_a;
    // r_b := cp.point_on_b;

    correct_position(rb0, rb1, cp);

    if !same_direction(rv, n) return;
    // ia := cross(cross(r_a, n), r_a)  * rb0.inverse_inertia_tensor;
    // ib := cross(cross(r_b, n), r_b)  * rb1.inverse_inertia_tensor;
    // d2 := dot(ia + ib, n);

    j := -(1 + cr) * dot(rv, n) / (d1);

    // rb0.position
    rb0.velocity -= (j * cp.normal) * rb0.inverse_mass;
    // rb0.angular_velocity -= cross(cp.point_on_a, (j * cp.normal)) * rb0.inverse_inertia_tensor;

    rb1.velocity += (j * cp.normal) * rb1.inverse_mass;
    // rb1.angular_velocity += cross(cp.point_on_b, (j * cp.normal)) * rb1.inverse_inertia_tensor;

    // print("RB0: %\n", (-j * cp.normal) * rb0.inverse_mass);
    // print("RB1: %\n", (j * cp.normal) * rb1.inverse_mass);
    //assert(false);
}


AABB :: struct {
    center: Vector3;
    halfs: Vector3;
}

make_AABB :: (center: Vector3, widths: Vector3) -> AABB {
    o: AABB = ---;
    o.center = center;
    o.halfs = widths * 0.5;
    return o;
}

Sphere :: struct {
    center: Vector3;
    radius: float;
}


// Y-axis-aligned capsule
Capsule :: struct {
    center: Vector3;
    radius: float;
    height: float;
}

make_Capsule :: (center: Vector3, radius: float, height: float) -> Capsule {
    cap: Capsule = ---;
    cap.center = center;
    cap.radius = radius;
    cap.height = height;
    return cap;
}

moment_of_inertia :: (s: Sphere, body: Rigid_Body) -> Matrix3 {
    m: Matrix3;
    t := 2.0 * ((1.0 / body.inverse_mass) * s.radius * s.radius) / 5.0;
    m.m[0][0] = t;
    m.m[1][1] = t;
    m.m[2][2] = t;
    return m;
}

moment_of_inertia :: (b: AABB, body: Rigid_Body) -> Matrix3 {
    w2 := b.halfs.x*2;
    w2 = w2*w2;

    h2 := b.halfs.y*2;
    h2 = h2*h2;

    d2 := b.halfs.z*2;
    d2 = d2*d2;

    mass := (1.0 / 12.0) * (1.0 / body.inverse_mass);

    m: Matrix3;
    m.m[0][0] = mass * (h2 + d2);
    m.m[1][1] = mass * (w2 + d2);
    m.m[2][2] = mass * (w2 + h2);
    return m;
}

moment_of_inertia :: (c: Capsule, body: Rigid_Body) -> Matrix3 {
    H := c.height;
    R := c.radius;

    r2 := R*R;
    r3 := r2*R;

    h2 := H*H;
    hr := H*R;

    mcy := H * r2 * PI;
    mhs := (2.0 * r3 * PI) / 3.0;
    m := mcy + 2 * mhs;

    p1 := mcy * (h2/12.0 +  r2/4.0) + (2 * mhs * ((2*r2/5.0) + (h2/2.0) + (3*hr/8.0)) );

    mat: Matrix3;
    mat.m[0][0] = p1;
    mat.m[1][1] = mcy*(r2/2.0) + 2*mhs*(2*r2/5.0);
    mat.m[2][2] = p1;
    return mat;
}

Ray :: struct {
    origin: Vector3;
    inv_dir: Vector3;
    dir: Vector3;
}

make_Ray :: (origin: Vector3, _dir: Vector3) -> Ray {
    r: Ray = ---;
    r.origin = origin;
    dir := normalize(_dir);
    // print("dir: %\n", dir);
    r.inv_dir = make_Vector3(1.0 / dir.x, 1.0 / dir.y, 1.0 / dir.z);
    // print("inv_dir: %\n", r.inv_dir);
    r.dir = dir;
    return r;
}

do_raycast :: (r: Ray, bodies: [] *Rigid_Body) -> *Rigid_Body, float {
    closest_dist: float = FLOAT32_MAX;
    closest_body: *Rigid_Body;

    for bodies {
        if it.shape_type == AABB {
            if do_ray_aabb_test(r, it.aabb) {
                dist := length(r.origin - it.aabb.center);
                if dist < closest_dist {
                    closest_dist = dist;
                    closest_body = it;
                }
            }
        }
    }

    return closest_body, closest_dist;
}

do_ray_aabb_test :: (r: Ray, aabb: AABB) -> bool {
    b_min := aabb.center - aabb.halfs;
    b_max := aabb.center + aabb.halfs;

    o := r.origin;
    inv := r.inv_dir;

    tx1 := (b_min.x - o.x) * inv.x;
    tx2 := (b_max.x - o.x) * inv.x;

    tmin := min(tx1, tx2);
    tmax := max(tx1, tx2);

    {
        ty1 := (b_min.y - o.y) * inv.y;
        ty2 := (b_max.y - o.y) * inv.y;

        tmin = max(tmin, min(ty1, ty2));
        tmax = min(tmax, max(ty1, ty2));
    }

    {
        tz1 := (b_min.z - o.z) * inv.z;
        tz2 := (b_max.z - o.z) * inv.z;

        tmin = max(tmin, min(tz1, tz2));
        tmax = min(tmax, max(tz1, tz2));
    }
    return tmax > max(tmin, 0.0);
}

// do_ray_sphere_test :: (r: Ray, sp: Sphere) -> bool {}

same_direction :: (a: Vector3, b: Vector3) -> bool {
    return dot(a, b) > 0;
}

ORIGIN: Vector3;

Contact_Point :: struct {
    normal: Vector3;
    dist: float;
    point_on_a: Vector3;
    point_on_b: Vector3;
}

// @Robustness handle the case where the sphere center is inside the AABB
do_collide_sphere_aabb :: (sp: Sphere, aabb: AABB) -> bool, Contact_Point {
    p := project_point_onto_aabb(sp.center, aabb);
    cp: Contact_Point;
    cp.normal = normalize(sp.center - p);
    cp.point_on_a = sp.radius * -cp.normal;
    cp.point_on_b = p - aabb.center; // @FixMe only true if the sphere center is outside the bounds of the AABB
    cp.dist = length((sp.center + cp.point_on_a) - p);
    return length(sp.center - p) < sp.radius, cp;
}

// @Incomplete the point_on_a is incorrect since the point is local the
// to the point we choose to do the sphere test and not the capsule center!
do_collide_capsule_aabb :: (cap: Capsule, aabb: AABB) -> bool, Contact_Point {
    ext := make_Vector3(0, cap.height/2.0, 0);
    min := cap.center - ext;
    max := cap.center + ext;
    p0 := project_point_onto_aabb(min, aabb);
    p1 := project_point_onto_aabb(max, aabb);

    sp: Sphere;
    sp.radius = cap.radius;
    if vectors_are_equal(p0, p1) { // if they're the same point, we're on top or below the box
        l1 := length(p0 - min);
        l2 := length(p1 - max);

        sp.center = min;
        if l2 < l1 {
            sp.center = max;
        }

        success, cp := do_collide_sphere_aabb(sp, aabb);
        return success, cp;
    }

    aabb_min := aabb.center + aabb.halfs;
    aabb_max := aabb.center + aabb.halfs;

    min_inside := aabb_min.y < min.y;
    max_inside := aabb_max.y > max.y;

    if min_inside && max_inside {
        // if both extents of the cylinder are inside, the point of contact
        // is square on with the center of the capsule
        sp.center = cap.center;
        success, cp := do_collide_sphere_aabb(sp, aabb);
        return success, cp;
    } else {
        // wichever dumbell end is physically closer to the box
        // @Cutnpaste from above
        l1 := length(p0 - min);
        l2 := length(p1 - max);

        sp.center = min;
        if l2 < l1 {
            sp.center = max;
        }

        success, cp := do_collide_sphere_aabb(sp, aabb);
        return success, cp;
    }
}

do_collide_aabb_aabb :: (a: AABB, b: AABB) -> bool, Contact_Point {
    a_min := a.center - a.halfs;
    a_max := a.center + a.halfs;

    b_min := b.center - b.halfs;
    b_max := b.center + b.halfs;

    cp: Contact_Point;

    if a_min.x > b_max.x || a_max.x < b_min.x return false, cp;
    if a_min.y > b_max.y || a_max.y < b_min.y return false, cp;
    if a_min.z > b_max.z || a_max.z < b_min.z return false, cp;
    
    p0 := b_max - a_min;
    p1 := a_max - b_min;

    x := min(p0.x, p1.x);
    y := min(p0.y, p1.y);
    z := min(p0.z, p1.z);

    // p2 := make_Vector3(x, y, z);
    // @Incomplete point_on_a, point_on_b
    if x < y && x < z {
        cp.normal = normalize(make_Vector3(x, 0, 0));
        cp.dist = cast(float32) abs(x);
        return true, cp;
    } else if y < z {
        cp.normal = normalize(make_Vector3(0, y, 0));
        cp.dist = cast(float32) abs(y);
        return true, cp;
    } else {
        cp.normal = normalize(make_Vector3(0, 0, z));
        cp.dist = cast(float32) abs(z);
        return true, cp;
    }
}

project_point_onto_aabb :: (p: Vector3, aabb: AABB) -> Vector3 {
    o: Vector3 = ---;
    min := aabb.center - aabb.halfs;
    max := aabb.center + aabb.halfs;
    o.x = clamp(p.x, min.x, max.x);
    o.y = clamp(p.y, min.y, max.y);
    o.z = clamp(p.z, min.z, max.z);
    return o;
}

closest_point_line_to_point :: (a: Vector3, b: Vector3, q: Vector3) -> Vector3 {
    invlen := 1.0 / length(b - a);
    n := (b - a) * invlen;

    u := dot((q - a), n) * invlen;
    v := dot((b - q), n) * invlen;

    if u <= 0 return b;
    if v <= 0 return a;
    else return u*a + v*b;
}


// based on Erin Catto's http://box2d.org/2014/02/computing-a-basis/
compute_basis :: (a: Vector3) -> Vector3, Vector3 {
    b: Vector3 = ---;
    if abs(a.x) > 0.57735 {
        b.x =  a.y;
        b.y = -a.x;
        b.z =  0;
    } else {
        b.x =  0;
        b.y =  a.z;
        b.z = -a.y;
    }

    b = normalize(b);
    c := cross(a, b);
    return b, c;
}

// @Return point on triangle; barycentric coordinates
// I'm pretty sure this doesn't clamp to the restraints of the triangle
closest_point_triangle_to_point :: (v0: Vector3, v1: Vector3, v2: Vector3, p: Vector3) -> Vector3, float, float, float {
    u := v1-v0;
    v := v2-v0;

    n := cross(u, v);
    w := p - v0;

    nl := dot(n, n);
    y := dot(cross(u, w), n) / nl;
    b := dot(cross(w, v), n) / nl;
    a := 1 - y - b;
    return v0*a + v1*b + v2*y, a, b, y;
}

// from Eberly's geometric tools https://www.geometrictools.com/Documentation/DistancePoint3Triangle3.pdf
// this can probably be simplified by just returing base, v1, v2 when the point q on the triangle plane is
// in regions 2, 4, or 6; this should work fine for the time being. -josh 7 November 2017
__closest_point_triangle_to_point :: (base: Vector3, v1: Vector3, v2: Vector3, target_point: Vector3) -> Vector3, float, float, float {
    base_to_point := base - target_point;
    e0 := v1 - base;
    e1 := v2 - base;

    a := dot(e0, e0);
    b := dot(e0, e1);
    c := dot(e1, e1);
    d := dot(e0, base_to_point);
    e := dot(e1, base_to_point);
    f := dot(base_to_point, base_to_point);

    s := b*e - c*d;
    t := b*d - a*e;
    det := a*c - b*b;

    if (s+t) <= det {
        if s < 0 {
            if t < 0 {
                t = 0;
                
                if -d >= a
                    s = 1;
                else
                    s = -d/a;
            } else {
                s = 0;

                if e >= 0
                    t = 0;
                else if -e >= c
                    t = 1;
                else
                    t = -e/c;
            }
        } else if t < 0 {
            t = 0;
            if d >= 0
                s = 0;
            else if -d >= a
                s = 1;
            else
                s = -d/a;
        } else {
            invdet := 1.0 / det;
            s *= invdet;
            t *= invdet;
        }
    } else {
        if s < 0 {
            t0 := b + d;
            t1 := c + e;

            if t1 > t0 {
                n := t1 - t0;
                den := a - 2*b + c;

                if n >= den
                    s = 1;
                else
                    s = n / den;

                t = 1 - s;
            } else {
                s = 0;

                if t1 <= 0
                    t = 1;
                if e >= 0
                    t = 0;
                else
                    t = -e/c;
            }
        } else if t < 0 {
            t0 := b + e;
            t1 := a + d;

            if t1 > t0 {
                n := t1 - t0;
                den := a - 2*b + c;

                if n >= den
                    t = 1;
                else
                    t = n / den;

                s = 1 - t;
            } else {
                t = 0;

                if t1 <= 0
                    s = 1;
                if d >= 0
                    s = 0;
                else
                    s = -d/a;
            }
        } else {
            n := (c + e) - (b + d);
            if n <= 0
                s = 0;
            else {
                den := a - 2*b + c;

                if n >= den
                    s = 1;
                else
                    s = n / den;
            }

            t = 1 - s;
        }
    }

    return base + e0*s + e1*t, s, t, 1.0 - (s+t);
}


// old stuff
/*

Support_Point :: struct {
    val: Vector3;
    val_a: Vector3;
    val_b: Vector3;
}

operator== :: (a: Support_Point, b: Support_Point) -> bool {
    return a.val == b.val; // ignore val_a and val_b for now
}

aabb_gjk_support :: (a: AABB, dir: Vector3) -> Vector3 {
    n := normalize(dir);

    min := a.center - a.halfs;
    max := a.center + a.halfs;

    out: Vector3 = ---;
    if n.x < 0 out.x = min.x;
    else out.x = max.x;
    if n.y < 0 out.y = min.y;
    else out.y = max.y;
    if n.z < 0 out.z = min.z;
    else out.z = max.z;
    return out;
}

sphere_gjk_support :: (a: Sphere, dir: Vector3) -> Vector3 {
    return a.center + (normalize(dir) * a.radius);
}

gjk_support :: (a: Rigid_Body, b: Rigid_Body, dir: Vector3) -> Support_Point {
    p: Support_Point = ---;
    p.val_a = a.support_func(*a.shape, dir);
    p.val_b = b.support_func(*b.shape, -dir);
    p.val = p.val_a - p.val_b;
    return p;
}

Simplex :: struct {
    a: Support_Point;
    b: Support_Point;
    c: Support_Point;
    d: Support_Point;
    count: u8;
}

add :: (using s: *Simplex, new_a: Support_Point) {
    if count == {
    case 0;
        a = new_a;
        count += 1;
        return;
    case 1;
        b = a;
        a = new_a;
        count += 1;
        return;
    case 2;
        c = b;
        b = a;
        a = new_a;
        count += 1;
        return;
    case 3;
        d = c;
        c = b;
        b = a;
        a = new_a;
        count += 1;
        return;
    }

    assert(false);
}

set :: (using s: *Simplex, args: .. Support_Point) {
    assert(args.count < 5);
    s.count = xx args.count;

    if args.count s.a = args[0];
    if args.count > 1 s.b = args[1];
    if args.count > 2 s.c = args[2];
    if args.count > 3 s.d = args[3];
}

do_triange_simplex :: (sim: *Simplex, a: Support_Point, b: Support_Point, c: Support_Point, ao: Vector3) -> Vector3 {
    ab := b.val - a.val;
    ac := c.val - a.val;
    abc := cross(ab, ac);
    v := __closest_point_triangle_to_point(a.val, b.val, c.val, ORIGIN);
    if length(v) < (EPSILON * EPSILON) {
        set(sim, sim.b, sim.c);
        return ao;
    }
    if same_direction(cross(abc, ac), ao) {
        if same_direction(ac, ao) {
            set(sim, a, c);
            return cross(ac, cross(ao, ac));
        } else if same_direction(ab, ao) {
            set(sim, a, b);
            return cross(ab, cross(ao, ab));
        } else {
            set(sim, a);
            return ao;
        }
    } else if same_direction(cross(ab, abc), ao) {
        if same_direction(ab, ao) {
            set(sim, a, b);
            return cross(ab, cross(ao, ab));
        } else {
            set(sim, a);
            return ao;
        }
    } else if same_direction(abc, ao) {
        set(sim, a, sim.b, sim.c);
        return abc;
    } else {
        set(sim, a, sim.c, sim.b);
        return -abc;
    }
}

do_simplex :: (sim: *Simplex, a: Support_Point) -> bool, Vector3 {
    ao := -a.val;

    if sim.count < 2 { // we should never actually hit these cases
        assert(false);
        return false, ao;
    }

    if sim.count == 2 {
        ab := sim.b.val - a.val;
        if same_direction(ab, ao) {
            return false, cross(ab, cross(ao, ab));
        } else {
            set(sim, a);
            return false, ao;
        }
    } else if sim.count == 3 {
        return false, do_triange_simplex(sim, a, sim.b, sim.c, ao);
    } else if sim.count == 4 {
        // bcd is our old triangle and we already know that the origin is in the direction of the normal of bcd
        // add_normal(m, c, b, d, green);
        // add_normal(m, a, b, c, green);
        // add_normal(m, a, c, d, green);
        // add_normal(m, a, d, b, green);

        bv := sim.b.val;
        cv := sim.c.val;
        dv := sim.d.val;
        av := a.val;

        abc := cross(bv - av, cv - av);
        acd := cross(cv - av, dv - av);
        adb := cross(dv - av, bv - av);
        if same_direction(abc, ao) {
            return false, do_triange_simplex(sim, a, sim.b, sim.c, ao);
        } else if same_direction(acd, ao) {
            return false, do_triange_simplex(sim, a, sim.c, sim.d, ao);
        } else if same_direction(adb, ao) {
            return false, do_triange_simplex(sim, a, sim.d, sim.b, ao);
        } else {
            return true, ao;
        }
    }

    assert(false);
    return false, ao;
}

do_gjk :: (obja: Rigid_Body, objb: Rigid_Body) -> bool, Simplex {
    sim: Simplex;
    d := normalize(make_Vector3(1, 1, 0));
    s := gjk_support(obja, objb, d);
    add(*sim, s);
    d = normalize(make_Vector3(1, -1, 0));

    while true {
        a := gjk_support(obja, objb, d);
        if dot(a.val, d) < 0 return false, sim;
        add(*sim, a);

        intersects: bool;
        intersects, d = do_simplex(*sim, a);
        if intersects return true, sim;
    }

    return false, sim;
}

Entry :: struct {
    p: [3] Support_Point;
    
    v: Vector3;
    vlen: float;
    y: [3] float;
    
    adj: [3] *Entry;
    j: [3] s32;
    internal: bool;
    obsolete: bool;
}

make_Entry :: (a: Support_Point, b: Support_Point, c: Support_Point) -> *Entry {
    e := New(Entry);
    e.p[0] = a;
    e.p[1] = b;
    e.p[2] = c;

    av := a.val;
    bv := b.val;
    cv := c.val;

    e.v, e.y[0], e.y[1], e.y[2] = __closest_point_triangle_to_point(av, bv, cv, ORIGIN);
    e.vlen = dot(e.v, e.v);
    assert(e.vlen > 0);
    internal := (e.y[0] >= 0 && e.y[0] <= 1) && (e.y[1] >= 0 && e.y[1] <= 1) && (e.y[2] >= 0 && e.y[2] <= 1);
    e.internal = internal;
    return e;
}

Set :: struct {
    e: *Entry;
    i: s32;
}

silhouette :: (e: *Entry, i: s32, w: Vector3, E: *[..] Set) {
    if !e.obsolete {
        if dot(e.v, w) < dot(e.v, e.v) {
            s: Set = ---;
            s.e = e;
            s.i = i;
            array_add(E, s);
        } else {
            e.obsolete = true;
            i0 := (i + 1) % 3;
            i1 := (i + 2) % 3;
            silhouette(e.adj[i0], e.j[i0], w, E);
            silhouette(e.adj[i1], e.j[i1], w, E);
        }
    }
}

do_epa :: (sim: Simplex, obja: Rigid_Body, objb: Rigid_Body) -> Contact_Point {
    Q: [..] *Entry;
    mu := 1000000.0;

    {
        a := sim.a;
        b := sim.b;
        c := sim.c;
        d := sim.d;

        cbd := make_Entry(c, b, d);
        abc := make_Entry(a, b, c);
        acd := make_Entry(a, c, d);
        adb := make_Entry(a, d, b);

        abc.adj[0] = adb;
        abc.adj[1] = cbd;
        abc.adj[2] = acd;
        abc.j[0] = 0;
        abc.j[1] = 0;
        abc.j[2] = 2;

        cbd.adj[0] = abc;
        cbd.adj[1] = adb;
        cbd.adj[2] = acd;
        cbd.j[0] = 1;
        cbd.j[1] = 1;
        cbd.j[2] = 1;
        
        acd.adj[0] = abc;
        acd.adj[1] = cbd;
        acd.adj[2] = adb;
        acd.j[0] = 2;
        acd.j[1] = 2;
        acd.j[2] = 0;

        adb.adj[0] = acd;
        adb.adj[1] = cbd;
        adb.adj[2] = abc;
        adb.j[0] = 0;
        adb.j[1] = 1;
        adb.j[2] = 2;

        array_add(*Q, cbd);
        array_add(*Q, abc);
        array_add(*Q, acd);
        array_add(*Q, adb);
    }

    cp: Contact_Point;
    while Q.count {
        entry := pop(*Q);

        if !entry.obsolete {
            v := entry.v;
            w := gjk_support(obja, objb, -v);
            mu = min(mu, dot(w.val, v));

            {
                cp.normal = normalize(v);
                cp.dist = length(v);

                {
                    a := entry.p[0].val_a;
                    b := entry.p[1].val_a;
                    c := entry.p[2].val_a;
                    cp.point_on_a = a*entry.y[0] + b*entry.y[1] + c*entry.y[2];
                }
                {
                    a := entry.p[2].val_b;
                    b := entry.p[1].val_b;
                    c := entry.p[0].val_b;
                    cp.point_on_b = a*entry.y[0] + b*entry.y[1] + c*entry.y[2];
                    
                }
            }

            if entry.vlen < mu {
                entry.obsolete = true;
                E: [..] Set;

                for 0..2 {
                    silhouette(entry.adj[it], entry.j[it], w.val, *E);
                }

                new_ents: [..] *Entry;
                for E {
                    ex := it.e;
                    i := it.i;
                    y := make_Entry(ex.p[(i+1)%3], entry.p[i], w);
                    y.adj[0] = ex;
                    y.j[0] = i;
                    ex.adj[i] = y;
                    ex.j[i] = 0;

                    array_add(*new_ents, y);
                }

                for new_ents {
                    ex1 := new_ents[(it_index+1) % new_ents.count];

                    it.adj[1] = ex1;
                    it.j[1] = 2;
                    ex1.adj[2] = it;
                    ex1.j[2] = 1;

                    if it.internal {
                        array_add(*Q, it);
                    }
                }
            } else {
                break;
            }
        }
    }
    return cp;
}

*/

/*

Segment :: struct {
    origin:    Vector3;
    direction: Vector3;
}

make_Segment :: (a: Vector3, b: Vector3) -> Segment {
    s: Segment = ---;
    s.origin = a;
    s.direction = b - a;
    return s;
}

Capsule :: struct {
    segment: Segment;
    radius: float;
}

make_Capsule :: (origin: Vector3, end: Vector3, radius: float) -> Capsule {
    out: Capsule = ---;
    out.segment.origin = origin;
    out.segment.direction = end - origin;
    out.radius = radius;
    return out;
}


do_intersect :: (s: Sphere, b: AABB) -> bool {
    sqr_dist: float64;
    d: float64;

    if s.center.x < b.xmin {
        d = s.center.x - b.xmin;
        sqr_dist += (d * d);
    } else if s.center.x > b.xmax {
        d = s.center.x - b.xmax;
        sqr_dist += (d * d);
    }

    if s.center.y < b.ymin {
        d = s.center.y - b.ymin;
        sqr_dist += (d * d);
    } else if s.center.y > b.ymax {
        d = s.center.y - b.ymax;
        sqr_dist += (d * d);
    }

    if s.center.z < b.zmin {
        d = s.center.z - b.zmin;
        sqr_dist += (d * d);
    } else if s.center.z > b.zmax {
        d = s.center.z - b.zmax;
        sqr_dist += (d * d);
    }

    return sqr_dist < (s.radius * s.radius);
}

do_overlap :: (a: Sphere, b: Sphere) -> bool {
    rad := a.radius + b.radius;
    return length(a.center - b.center) <= rad;
}

do_overlap :: (a: Capsule, b: Capsule) -> bool {
    rad := a.radius + b.radius;
    dist := distance(a.segment, b.segment);
    return dist <= rad;
}

will_overlap :: (tmin: float, tmax: float, s0: Sphere, v0: Vector3, s1: Sphere, v1: Vector3) -> bool {
    c0 := make_Capsule(s0.center + v0*tmin, s0.center + v0*tmax, s0.radius);
    c1 := make_Capsule(s1.center + v1*tmin, s1.center + v1*tmax, s1.radius);

    return do_overlap(c0, c1);
}

NEAR_ZERO :: 0.00000001;

distance :: (p: Segment, q: Segment) -> float, Segment {
    w0 := p.origin - q.origin;
    a := dot(p.direction, p.direction);
    b := dot(p.direction, q.direction);
    c := dot(q.direction, q.direction);
    d := dot(p.direction, w0);

    det := (a * c) - (b * b)
    sc: float;
    tc: float;

    if det < NEAR_ZERO {
        sc = 0;
        tc = d / b;
    } else {
        e := dot(q.direction, w0);
        sc := ((b * e) - (c * d)) / det;
        tc := ((a * e) - (b * d)) / det;
    }

    point0 := p.origin + (p.direction * sc);
    point1 := q.origin + (q.direction * tc);

    out_segment: Segment = ---;
    out_segment.origin = point0;
    out_segment.direction = point1 - point0;
    return length(out_segment.direction), out_segment;
}
*/