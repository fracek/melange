documented: #t
module: c-declarations
copyright: Copyright (C) 1994, Carnegie Mellon University
	   All rights reserved.
	   This code was produced by the Gwydion Project at Carnegie Mellon
	   University.  If you are interested in using this code, contact
	   "Scott.Fahlman@cs.cmu.edu" (Internet).
rcs-header: $Header: 

//======================================================================
//
// Copyright (c) 1994  Carnegie Mellon University
// All rights reserved.
//
//======================================================================

//======================================================================
// c-decl.dylan encapsulates definitions and "standard" functions for the
// <declaration> class.  Other files in the c-declarations model handle the
// interface to the parser (c-decl-state.dylan) and write out dylan code
// corresponding to the declarations (c-decl-write.dylan).
//
// The operations defined in this file are designed to be called from
// "define-interface" in a set order.  This ordering is shown in the exports
// list below.
//======================================================================

define module c-declarations
  use dylan;
  use extensions, exclude: {format, <string-table>};
  use regular-expressions;
  use streams;
  use format;

  // We completely encapsulate "c-parse" and only pass out the very few 
  // objects that will be needed by "define-interface".  Note that the 
  // classes are actually defined within this module but are exported
  // from c-parse.
  use c-parse, export: {<declaration>, <parse-state>, parse, parse-type,
			constant-value, true-type};

  use c-lexer;			// Tokens are used in process-type-list and
				// make-struct-type

  export
    // Basic type declarations
    <function-declaration>, <structured-type-declaration>,
    <struct-declaration>, <union-declaration>, <variable-declaration>,
    <constant-declaration>, <typedef-declaration>, 

    // Preliminary "set declaration properties phase"
    ignored?-setter, find-result, find-parameter, find-slot,
    argument-direction-setter, constant-value-setter, getter-setter,
    setter-setter, read-only-setter, sealed-string-setter, excluded?-setter,
    exclude-slots, equate, remap, rename, superclasses-setter,

    // "Import declarations phase" 
    declaration-closure, // also calls compute-closure

    // "Name computation phase"
    apply-options, apply-container-options, // also calls find-dylan-name,
					    // compute-dylan-name

    // "Write declaration phase"
    write-declaration, 
    write-file-load, write-mindy-includes,

    // Miscellaneous
    getter, setter, sealed-string, excluded?,
    canonical-name,declarations;
end module c-declarations;

//------------------------------------------------------------------------
// <declaration>
//
// This section contains definitions and functions common to all (or most)
// declarations. 
//------------------------------------------------------------------------
// The class hierarchy for declarations includes the following:
//   <declaration>
//        operations include mapped-name, remap, dylan-name,
//        compute-dylan-name, rename, equate, canonical-name, type-name,
//        compute-closure, find-dylan-name, apply-options
//     <type-declaration>
//         operations include true-type, pointer-to, c-type-size
//       <structured-type-declaration>
//            operations include find-slot, exclude-slots, make-struct-type,
//            members, apply-container-options
//         <struct-type-declaration>
//         <union-type-declaration>
//         <enum-declaration>
//       <pointer-declaration>
//            operations include referent, pointer-to
//       <function-type-declaration>
//           operations include find-parameter, find-result
//       <typedef-declaration> (uses <typed> mixin)
//       <incomplete-type-declaration>
//       <predefined-type-declaration>
//         <integer-type-declaration>
//             operations include accessor-name
//         <float-type-declaration>
//     <value-declaration> (includes <typed> mixin)
//         operations include sealed-string
//       <function-declaration>
//           operations include find-parameter, find-result
//       <object-declaration>
//           operations include equated and read-only
//         <variable-declaration>
//             operations include getter and setter
//         <slot-declaration>
//             operations include excluded?
//         <result-declaration>
//             operations include ignored?-setter
//         <arg-declaration>
//             operations include direction, original-type,
//             argument-direction-setter
//           <varargs-declaration>
//     <constant-declaration>
//         operations include constant-value
//       <enum-slot-declaration>
//       <macro-declaration>
//           operations include add-cpp-declaration
//   <typed> (Mix-in class)
//     operations include type
//   <new-static-pointer> (Mix-in class)
//     Corresponds to new types which will be subtypes of
//     <statically-typed-pointer>.  Operations include superclasses.
//------------------------------------------------------------------------

// A <declaration> can correspond to any sort of declaration that might appear
// in a C header file.
//
define abstract class <declaration> (<object>)
  slot simple-name :: <string>, required-init-keyword: #"name";
  slot c-name :: union(<string>, <false>), init-value: #f;
  slot d-name :: union(<string>, <false>),
    init-value: #f, init-keyword: #"dylan-name";
  slot map-type :: union(<string>, <false>), init-value: #f;
  slot declared? :: <boolean>, init-value: #f;
end class <declaration>;

define abstract class <typed> (<object>)
  slot type :: <type-declaration>, required-init-keyword: #"type";
end class <typed>;

// The following operations are defined upon some or all declarations.
// Method definitions occur with the appropriate subclasses.

// Returns the dylan type to which the declaration is mapped.  (For object
// declarations, this will be the mapped version of the object's type, for
// type declarations it will be the mapped versions of that type.)
//
// The "explicit-only:" keyword is for internal use only.  It instructs
// "mapped-name" to simply return #f if no explicit mapping has been specified
// for the given declaration.
//
define generic mapped-name
    (decl :: <declaration>, #key) => (result :: union(<string>, <false>));

// Sets the mapped name for a given type (or for an object's type).
//
define generic remap (decl :: <declaration>, name :: <string>) => ();

// Returns the dylan name for this object or type.  This name is independent
// of mapping, but may be changed by renaming or equating.
//
define generic dylan-name (decl :: <declaration>) => (result :: <string>);
define generic dylan-name-setter
    (value :: <string>, decl :: <declaration>) => (result :: <string>);

// Computes an appropriate name for object or type declarations whose names
// haven't already been explicitly set.  Should also recursively call
// "find-dylan-name" (defined in "c-decl-write.dylan") on any declarations
// referenced by this declaration.  Typically just calls the given
// "name-mapper" function with an appropriate "category" argument.
//
define generic compute-dylan-name
    (decl :: <declaration>, mapper :: <function>, prefix :: <string>,
     containers :: <sequence>, rd-only :: <boolean>, sealing :: <string>)
 => (result :: <string>);

// Find-dylan-name provlides low level support for "apply-options".  It checks
// whether various attributes need to be computed and calls the computation
// functions as required and can be called recursively to deal with nested
// components.
//
define generic find-dylan-name
    (decl :: <declaration>, mapper :: <function>, prefix :: <string>,
     containers :: <sequence>, read-only :: <boolean>, sealing :: <string>)
 => (result :: <string>);

// Sets the dylan name for this object or type.  (External interface.)
//
define generic rename (decl :: <declaration>, name :: <string>) => ();

// Sets the dylan type to which this type (or this object's type) is
// equivalent.  This is like renaming, but also implies that the dylan type
// already exists.
//
define generic equate (decl :: <declaration>, name :: <string>) => ();

// Returns/computes the string/name by which a type or object can be named in
// a "define interface" clause.  This may be replaced by a more general
// mechanism later.
//
define generic canonical-name (decl :: <declaration>) => (result :: <string>);

// Returns the dylan name of a type or of an object's type.  Since it takes
// into account "equate" clauses on both types and objects, it is different
// from "object.type.dylan-name".
//
define generic type-name (decl :: <declaration>) => (result :: <string>);

// Look up the given pointer type in the state's pointer table, and create it
// if it doesn't yet exist.  (The definition of this function is bundled with
// the definitions for <pointer-declaration>.)
//
define generic pointer-to
    (target-type :: <type-declaration>, state :: <parse-state>)
 => (ptr-type :: <pointer-declaration>);

// This is the exported function which computes various properties of a C
// declarations based upon user specified options.  This includes name
// computation, read-only declarations, and method sealing.
//
// The parameters should correspond to the global values for these options.
// If the declaration had any more specific names or options set earlier than
// they will remain in force in spite of calls to "apply-options".
//
define generic apply-options
    (decl :: <declaration>, map-function :: <function>, prefix :: <string>,
     read-only :: <boolean>, sealing :: <string>)
 => ();

//------------------------------------------------------------------------

define method mapped-name
    (decl :: <declaration>, #key explicit-only?)
 => (result :: union(<string>, <false>));
  decl.map-type | (~explicit-only? & decl.type-name);
end method mapped-name;

define method remap (decl :: <declaration>, name :: <string>) => ();
  decl.map-type := name;
end method remap;

// Find-dylan-name provides low level support for "apply-options".  It checks
// whether various attributes need to be computed and calls the computation
// functions as required and can be called recursively to deal with nested
// components.
//
define method find-dylan-name
    (decl :: <declaration>, mapper :: <function>, prefix :: <string>,
     containers :: <sequence>, read-only :: <boolean>, sealing :: <string>)
 => (result :: <string>);
  decl.d-name
    | (decl.d-name := compute-dylan-name(decl, mapper, prefix, containers,
					 read-only, sealing));
end method find-dylan-name;

define method dylan-name (decl :: <declaration>) => (result :: <string>);
  // The name should always be computed by compute-dylan-name before we ask
  // for it.  This routine explicitly verifies this.
  decl.d-name | error("No dylan name defined for %=", decl);
end method dylan-name;

define method dylan-name-setter
    (value :: <string>, decl :: <declaration>) => (result :: <string>);
  decl.d-name := value;
end method dylan-name-setter;

define method rename (decl :: <declaration>, name :: <string>) => ();
  decl.dylan-name := name;
end method rename;

define method canonical-name (decl :: <declaration>) => (result :: <string>);
  // The "canonical name" for most declarations is the same as the "simple
  // name". 
  decl.c-name | (decl.c-name := decl.simple-name);
end method canonical-name;

define method compute-closure 
    (results :: <deque>, decl :: <declaration>) => (results :: <deque>);
  // For simple declarations, we simply check whether the type has already be
  // "declared" and add it to the result otherwise.  Other methods may call
  // this one after doing recursive declarations.
  if (~decl.declared?)
    decl.declared? := #t;
    push-last(results, decl);
  end if;
  results;
end method compute-closure;

define method apply-options
    (decl :: <declaration>, map-function :: <function>, prefix :: <string>,
     read-only :: <boolean>, sealing :: <string>)
 => ();
  find-dylan-name(decl, map-function, prefix, #(), read-only, sealing);
end method apply-options;

//------------------------------------------------------------------------
// Type declarations
//------------------------------------------------------------------------

define abstract class <type-declaration> (<declaration>)
  slot equated? :: <boolean>, init-value:  #f, init-keyword: #"equated";
end class;

define abstract class <new-static-pointer> (<object>)
  slot superclasses :: false-or(<sequence>), init-value: #f;
end class <new-static-pointer>;

// Pushes past any typedefs to find an actual "structured" type declaration.
// Should only be used in calls of the form: instance?(foo.true-type, <bar>)
//
define generic true-type (type :: <type-declaration>);

// Returns the number of bytes required to store instances of some C type.
// Portability note: these sizes should hold true for "typical" C compilers on
// 16 and 32 bit machines.  However, they may well need to be customized for
// other architectures or C compilers.
//
define generic c-type-size (type :: <type-declaration>);

//------------------------------------------------------------------------

define method equate (decl :: <type-declaration>, name :: <string>) => ();
  if (instance?(decl.true-type, <predefined-type-declaration>))
    error("Cannot 'equate:' predefined type: %s.", decl.simple-name);
  end if;
  decl.dylan-name := name;
  decl.equated? := #t;
end method equate;

define method compute-dylan-name
    (decl :: <type-declaration>, mapper :: <function>, prefix :: <string>,
     containers :: <sequence>, rd-only :: <boolean>, sealing :: <string>)
 => (result :: <string>);
  mapper(#"type", prefix, decl.simple-name, containers);
end method compute-dylan-name;

define method type-name (decl :: <type-declaration>) => (result :: <string>);
  decl.dylan-name;
end method type-name;

define method true-type (type :: <type-declaration>)
  type;
end method true-type;

// Returns the number of bytes required to store instances of some C type.
// Portability note: these sizes should hold true for "typical" C compilers on
// 16 and 32 bit machines.  However, they may well need to be customized for
// other architectures or C compilers.
//
define method c-type-size (type :: <type-declaration>)
 => size :: <integer>;
  0;
end method c-type-size;

//------------------------------------------------------------------------

define abstract class <structured-type-declaration> (<type-declaration>) 
  slot members :: union(<sequence>, <false>), init-value: #f;
end class <structured-type-declaration>;
define class <struct-declaration>
    (<new-static-pointer>, <structured-type-declaration>)
end class;
define class <union-declaration>
    (<new-static-pointer>, <structured-type-declaration>)
end class;
define class <enum-declaration> (<structured-type-declaration>) end class;

// Given a function (or function type) declaration, return the declaration
// corresponding to its result type.
//
define generic find-slot
    (decl :: <structured-type-declaration>, name :: <string>) 
 => (result :: <declaration>);

// Removes any slots which were explicitly excluded or, if import-all? is
// false, which are not explictly imported.
//
define generic exclude-slots
    (decl :: <structured-type-declaration>,
     imports :: <explicit-key-collection>, import-all? :: <boolean>);

// Operation called by the parser to define a new structured (i.e. struct, 
// union, or enum) type.  The appropriate declaration class is computed from
// the given token.
//
define generic make-struct-type
    (name :: union(<string>, <false>), member-list :: union(<list>, <false>),
     token :: <token>, state :: <parse-state>)
 => (result :: <structured-type-declaration>);

// This function is analogous to "apply-options" except that it is called upon
// a specific structured type and applies the options to all "members" of
// that type.  Like "apply-options" it will avoid modifying any names or
// options that might have been set by earlier calls.
//
define generic apply-container-options
    (decl :: <structured-type-declaration>,
     map-function :: <function>, prefix :: <string>, read-only :: <boolean>,
     sealing :: <string>)
 => ();

define method compute-closure 
    (results :: <deque>,
     decl :: union(<struct-declaration>, <union-declaration>))
 => (results :: <deque>);
  if (~decl.declared?)
    decl.declared? := #t;
    if (decl.members)
      for (elem in decl.members)
	if (~elem.excluded?) compute-closure(results, elem.type) end if;
      end for;
    end if;
    push-last(results, decl);
  end if;
  results;
end method compute-closure;

define method canonical-name (decl :: <struct-declaration>)
 => (result :: <string>);
  decl.c-name | (decl.c-name := concatenate("struct ", decl.simple-name));
end method canonical-name;

define method canonical-name (decl :: <union-declaration>)
 => (result :: <string>);
  decl.c-name | (decl.c-name := concatenate("union ", decl.simple-name));
end method canonical-name;

define method canonical-name (decl :: <enum-declaration>)
 => (result :: <string>);
  decl.c-name | (decl.c-name := concatenate("enum ", decl.simple-name));
end method canonical-name;

define method make-enum-slot
    (name :: <string>, value :: false-or(<integer>),
     prev :: false-or(<enum-slot-declaration>), state :: <parse-state>)
 => (result :: <enum-slot-declaration>);
  if (key-exists?(state.objects, name))
    parse-error(state, "Enumeration literal does not have a unique name: %s",
		name);
  else
    let value
      = case
	  value => value;
	  prev => prev.constant-value + 1;
	  otherwise => 0;
	end case;
    state.objects[name] := add-declaration(state,
					   make(<enum-slot-declaration>,
						name: name, value: value))
  end if;
end method make-enum-slot;

define method make-struct-type
    (name :: union(<string>, <false>), member-list :: union(<list>, <false>),
     decl-token :: <token>, state :: <parse-state>)
 => (result :: <structured-type-declaration>);
  let declaration-class = select (decl-token by instance?)
			    <enum-token> => <enum-declaration>;
			    <struct-token> => <struct-declaration>;
			    <union-token> => <union-declaration>;
			  end select;

  let true-name = name | anonymous-name();
  let old-type = element(state.structs, true-name, default: #f);
  let type
    = if (old-type)
	if (object-class(old-type) ~= declaration-class)
	  parse-error(state,
		      "Struct or union type doesn't match original "
			"declaration: %s",
		      true-name);
	end if;
	old-type;
      elseif (~instance?(state, <parse-file-state>))
	parse-error(state, "Type not found: %s.", true-name);
      else
	state.structs[true-name]
	  := add-declaration(state, make(declaration-class, name: true-name));
      end if;

  // "process-member" will make slot or "enum slot" declarations for the raw
  // data returned by the parser.  For enum slots, this includes calculating
  // the value if wasn't already specified.
  let last :: <integer> = -1;
  let process-member
    = if (declaration-class == <enum-declaration>)
	method (elem)
	  elem;
	end method;
      else
	method (elem :: <pair>)
	  make(<slot-declaration>, name: elem.head, type: elem.tail);
	end method;
      end if;

  if (member-list)
    if (type.members)
      parse-error(state, "Can't declare structure twice: %s.", true-name);
    else
      type.members := map(process-member, member-list);
    end if;
  end if;
  type;
end method make-struct-type;

define method find-slot
    (decl :: <structured-type-declaration>, name :: <string>) 
 => (result :: <declaration>);
  any?(method (member) member.simple-name = name & member end method,
       decl.members) | error("No such slot: %s", name);
end method find-slot;

define method exclude-slots
    (decl :: <structured-type-declaration>,
     imports :: <explicit-key-collection>, import-all? :: <boolean>)
 => ();
  for (member in decl.members)
    member.excluded? := ~element(imports, member, default: import-all?);
  end for;
end method exclude-slots;

define method find-dylan-name
    (decl :: <structured-type-declaration>, mapper :: <function>,
     prefix :: <string>, containers :: <sequence>, read-only :: <boolean>,
     sealing :: <string>)
 => (result :: <string>);
  // Take care of the contained objects as well.  Some of these may
  // already have been handled by "container" declarations.
  let sub-containers = list(decl.simple-name);
  if (decl.members)
    for (sub-decl in decl.members)
      find-dylan-name(sub-decl, mapper, prefix, sub-containers,
		      read-only, sealing);
    end for;
  end if;

  decl.d-name
    | (decl.d-name := compute-dylan-name(decl, mapper, prefix, containers,
					 read-only, sealing));
end method find-dylan-name;

define method apply-container-options
    (decl :: <structured-type-declaration>,
     map-function :: <function>, prefix :: <string>, read-only :: <boolean>,
     sealing :: <string>)
 => ();
  let sub-containers = list(decl.simple-name);
  for (elem in decl.members)
    find-dylan-name(elem, map-function, prefix, sub-containers, read-only,
		    sealing);
  end for;
end method apply-container-options;

define method c-type-size (decl :: <union-declaration>) => size :: <integer>;
  reduce(method (sz, member) max(sz, c-type-size(member.type)) end method,
	 0, decl.members);
end method c-type-size;

// Returns both the start and end of the memory occupied by the given slot,
// given that the previous slot ended at "prev-slot-end".  This takes into
// account alignment restrictions on pointers and builtin types.  (Portability
// note: these alignment restrictions are typical on current UNIX (tm)
// machines, but may not apply to *all* machines.)
//
define method aligned-slot-position
    (prev-slot-end :: <integer>, slot-type :: <type-declaration>)
 => (this-slot-end :: <integer>, this-slot-start :: <integer>);
  if (instance?(slot-type, <typedef-declaration>))
    aligned-slot-position(prev-slot-end, slot-type.type);
  else 
    let (size, alignment)
      = select (slot-type by instance?)
	  <predefined-type-declaration>, <function-type-declaration>,
	  <pointer-declaration>, <enum-declaration> => 
	    let sz = c-type-size(slot-type);
	    values(sz, sz);
	  <struct-declaration>, <union-declaration>, <vector-declaration> =>
	    // Portability note: Assume that inlined structs, unions, and
	    // vectors will be word aligned.
	    values(c-type-size(slot-type), 4);
	  otherwise =>
	    error("Unhandled c type in aligned-slot-position");
	end select;
    let alignment-temp = prev-slot-end + alignment - 1;
    let slot-start = alignment-temp - remainder(alignment-temp, alignment);
    values(slot-start + size, slot-start);
  end if;
end method aligned-slot-position;

define method c-type-size (decl :: <struct-declaration>) => size :: <integer>;
  if (decl.members)
    reduce(method (sz, member) aligned-slot-position(sz,member.type) end,
	   0, decl.members);
  else
    0;
  end if;
end method c-type-size;

define method c-type-size (type :: <enum-declaration>) => size :: <integer>;
  // Portability note: This should be standard for 16 and 32 bit machines, but
  // is not guaranteed in the ref manual.
  4;
end method c-type-size;

//------------------------------------------------------------------------

define class <pointer-declaration> (<new-static-pointer>, <type-declaration>)
  slot referent :: <type-declaration>, required-init-keyword: #"referent";
  slot accessors-written?, init-value: #f;
end class;

define class <vector-declaration> (<new-static-pointer>, <type-declaration>)
  slot pointer-equiv :: <type-declaration>, required-init-keyword: #"equiv";
  slot length :: union(<integer>, <false>), required-init-keyword: #"length";
end class <vector-declaration>;

define method mapped-name
    (decl :: <pointer-declaration>, #key explicit-only?)
 => (result :: union(<string>, <false>));
  if (decl.simple-name = decl.referent.simple-name)
    decl.map-type | decl.referent.map-type
      | (~explicit-only? & decl.type-name);
  else
    decl.map-type | (~explicit-only? & decl.type-name);
  end if;
end method mapped-name;

define method mapped-name
    (decl :: <vector-declaration>, #key explicit-only?)
 => (result :: union(<string>, <false>));
  decl.map-type | decl.pointer-equiv.map-type
    | (~explicit-only? & decl.type-name);
end method mapped-name;

define method canonical-name (decl :: <pointer-declaration>)
 => (result :: <string>);
  if (decl.c-name)
    decl.c-name;
  else
    for (referent-type = decl.referent then referent-type.referent,
	 suffix = "*" then concatenate(suffix, "*"),
	 while instance?(referent-type, <pointer-declaration>))
    finally
      select (referent-type by instance?)
	<vector-declaration> =>
	  let referent-name = referent-type.canonical-name;
	  let sub-name = referent-type.pointer-equiv.referent.canonical-name;
	  decl.c-name
	    := concatenate(sub-name, suffix,
			   copy-sequence(referent-name, start: sub-name.size));
	<function-type-declaration> =>
	  let referent-name = referent-type.canonical-name;
	  let sub-name = referent-type.result.canonical-name;
	  decl.c-name := format-to-string("%s (%s)", sub-name,
					  copy-sequence(referent-name,
							start: sub-name.size));
	otherwise =>
	  decl.c-name := concatenate(referent-type.canonical-name, suffix);
      end select;
    end for;
  end if;
end method canonical-name;

define method canonical-name (decl :: <vector-declaration>)
 => (result :: <string>);
  decl.c-name
    | (decl.c-name := concatenate(decl.pointer-equiv.referent.canonical-name,
				  "[]"));
end method canonical-name;

define method compute-dylan-name
    (decl :: <pointer-declaration>, mapper :: <function>, prefix :: <string>,
     containers :: <sequence>, rd-only :: <boolean>, sealing :: <string>)
 => (result :: <string>);
  if (decl.simple-name = decl.referent.simple-name)
    find-dylan-name(decl.referent, mapper, prefix, #(), rd-only, sealing);
  else
    mapper(#"type", prefix, decl.simple-name, containers);
  end if;
end method compute-dylan-name;
  
define method compute-closure 
    (results :: <deque>, decl :: <pointer-declaration>)
 => (results :: <deque>);
  if (~decl.declared?)
    decl.declared? := #t;
    compute-closure(results, decl.referent);
    push-last(results, decl);
  end if;
  results;
end method compute-closure;

define method compute-dylan-name
    (decl :: <vector-declaration>, mapper :: <function>, prefix :: <string>,
     containers :: <sequence>, rd-only :: <boolean>, sealing :: <string>)
 => (result :: <string>);
  mapper(#"type", prefix, decl.simple-name, containers);
end method compute-dylan-name;

define method compute-closure 
    (results :: <deque>, decl :: <vector-declaration>) => (results :: <deque>);
  if (~decl.declared?)
    decl.declared? := #t;
    compute-closure(results, decl.pointer-equiv);
    push-last(results, decl);
  end if;
  results;
end method compute-closure;

// Look up the given pointer type in the state's pointer table, and create it
// if it doesn't yet exist.  
//
define method pointer-to
    (target-type :: <type-declaration>, state :: <parse-state>)
 => (ptr-type :: <pointer-declaration>);
  let found-type = element(state.pointers, target-type, default: #f);
  if (found-type)
    found-type;
  else
    let new-type
      = select (target-type.true-type by instance?)
	  <pointer-declaration>, <function-type-declaration>,
	  <predefined-type-declaration> =>
	    make(<pointer-declaration>, name: anonymous-name(),
		 referent: target-type);
	  otherwise =>
	    // Pointers to struct types are the same as the types themselves.
	    // Therefore we create a dummy entry with the same name.  This
	    // gets special treatment in several places.
	    make(<pointer-declaration>, referent: target-type,
		 name: target-type.simple-name);
	end select;
    state.pointers[target-type] := new-type;
    new-type;
  end if;
end method pointer-to;

define method c-type-size (pointer :: <pointer-declaration>)
 => size :: <integer>;
  // Portability note: This assumption should hold true on most 16 and 32 bit
  // machines. 
  4;
end method c-type-size;

define method c-type-size (vector :: <vector-declaration>)
 => size :: <integer>;
  // Portability note: Might some compilers do alignment of elements?
  vector.pointer-equiv.referent.c-type-size * (vector.length | 0);
end method c-type-size;

//------------------------------------------------------------------------

define class <function-type-declaration> (<type-declaration>)
  slot result :: <result-declaration>, required-init-keyword: #"result";
  slot parameters :: <sequence>, required-init-keyword: #"params";
end class <function-type-declaration>;

define method canonical-name (decl :: <function-type-declaration>)
 => (result :: <string>);
  if (decl.c-name)
    decl.c-name
  else
    // We need to include the actual parameters eventually.  This is a stopgap
    // to guarantee that all function declarations will end up in the name
    // table. 
    format-to-string("%s (%s)", decl.result.canonical-name,
		     decl.simple-name);
  end if;
end method canonical-name;

define method find-dylan-name
    (decl :: <function-type-declaration>, mapper :: <function>,
     prefix :: <string>, containers :: <sequence>, read-only :: <boolean>,
     sealing :: <string>)
 => (result :: <string>);
  find-dylan-name(decl.result, mapper, prefix, #(), read-only,
		  sealing);
  for (elem in decl.parameters)
    if (~instance?(elem, <varargs-declaration>))
      find-dylan-name(elem, mapper, prefix, #(), read-only, sealing);
    end if; 
  end for;

  decl.d-name
    | (decl.d-name := compute-dylan-name(decl, mapper, prefix, containers,
					 read-only, sealing));
end method find-dylan-name;

define method compute-dylan-name
    (decl :: <function-type-declaration>, mapper :: <function>,
     prefix :: <string>, containers :: <sequence>, rd-only :: <boolean>,
     sealing :: <string>)
 => (result :: <string>);
  mapper(#"type", prefix, decl.simple-name, containers);
end method compute-dylan-name;

define method compute-closure 
    (results :: <deque>, decl :: <function-type-declaration>)
 => (results :: <deque>);
  if (~decl.declared?)
    decl.declared? := #t;

    compute-closure(results, decl.result);
    for (elem in decl.parameters)
      if (~instance?(elem, <varargs-declaration>))
	compute-closure(results, elem)
      end if; 
    end for;

    push-last(results, decl);
  end if;
  results;
end method compute-closure;

define method c-type-size (type :: <function-type-declaration>)
 => size :: <integer>;
  // Portability note: This assumption should hold true on most 16 and 32 bit
  // machines. 
  4;
end method c-type-size;

//------------------------------------------------------------------------

define class <typedef-declaration> (<type-declaration>, <typed>) end class;

define method mapped-name
    (decl :: <typedef-declaration>, #key explicit-only?)
 => (result :: union(<string>, <false>));
  decl.map-type | decl.type.map-type | (~explicit-only? & decl.type-name);
end method mapped-name;

define method compute-dylan-name
    (decl :: <typedef-declaration>, mapper :: <function>, prefix :: <string>,
     containers :: <sequence>, rd-only :: <boolean>, sealing :: <string>)
 => (result :: <string>);
  mapper(#"type", prefix, decl.simple-name, containers);
end method compute-dylan-name;

define method compute-closure 
    (results :: <deque>, decl :: <typedef-declaration>)
 => (results :: <deque>);
  if (~decl.declared?)
    decl.declared? := #t;
    compute-closure(results, decl.type);
    push-last(results, decl);
  end if;
  results;
end method compute-closure;

define method true-type (alias :: <typedef-declaration>)
  true-type(alias.type);
end method true-type;

define method c-type-size (typedef :: <typedef-declaration>)
 => size :: <integer>;
  c-type-size(typedef.type);
end method c-type-size;

//------------------------------------------------------------------------

define class <incomplete-type-declaration> (<type-declaration>) end class;

define class <predefined-type-declaration> (<type-declaration>) 
  slot c-type-size :: <integer>, required-init-keyword: #"size";
end class;

define class <integer-type-declaration> (<predefined-type-declaration>)
  // Accessor-name specifies the "dereference" function to call in order to
  // retrieve the correct number of bytes.
  slot accessor-name :: <string>, required-init-keyword: #"accessor";
end class;

define class <float-type-declaration> (<predefined-type-declaration>)
end class;

define constant unknown-type = make(<incomplete-type-declaration>,
				    name: "machine-pointer");
define constant unsigned-type = make(<incomplete-type-declaration>,
				     name: "unknown-type");
define constant signed-type = make(<incomplete-type-declaration>,
				   name: "unknown-type");
define constant void-type = make(<predefined-type-declaration>,
				 dylan-name: "<void>",
				 name: "void-type", size: 0);

// Portability note: The type sizes given here are typical for 32 bit
// machines, but may not be accurate for 16 and 64 bit machines.
define constant int-type = make(<integer-type-declaration>,
				accessor: "signed-long-at",
				name: "int",
				dylan-name: "<integer>", size: 4);
define constant unsigned-int-type = make(<integer-type-declaration>,
					 accessor: "unsigned-long-at",
					 name: "unsigned int",
					 dylan-name: "<integer>", size: 4);
define constant short-type = make(<integer-type-declaration>,
				  accessor: "signed-short-at",
				  name: "short",
				  dylan-name: "<integer>", size: 2);
define constant unsigned-short-type = make(<integer-type-declaration>,
					   accessor: "unsigned-short-at",
					   name: "unsigned short",
					   dylan-name: "<integer>", size: 2);
define constant long-type = make(<integer-type-declaration>,
				 accessor: "signed-long-at",
				 name: "long",
				 dylan-name: "<integer>", size: 4);
define constant unsigned-long-type = make(<integer-type-declaration>,
					  accessor: "unsigned-long-at",
					  name: "unsigned long",
					  dylan-name: "<integer>", size: 4);
define constant char-type = make(<integer-type-declaration>,
				 accessor: "signed-byte-at",
				 name: "char",
				 dylan-name: "<integer>", size: 1);
define constant unsigned-char-type = make(<integer-type-declaration>,
					  accessor: "unsigned-byte-at",
					  name: "unsigned char",
					  dylan-name: "<integer>", size: 1);
define constant float-type = make(<float-type-declaration>,
				  name: "float",
				  dylan-name: "<float>", size: 4);
define constant double-type = make(<float-type-declaration>,
				   name: "double",
				   dylan-name: "<float>", size: 8);
define constant long-double-type = make(<float-type-declaration>,
					name: "double",
					dylan-name: "<float>", size: 16);

define method compute-closure 
    (results :: <deque>, decl :: <predefined-type-declaration>)
 => (results :: <deque>);
  // We don't need to declare it -- it's predefined.
  results;
end method compute-closure;

//------------------------------------------------------------------------

define abstract class <value-declaration> (<declaration>, <typed>)
  slot sealed-string :: <string>, init-value: "";
end class;
define class <function-declaration> (<value-declaration>) end class;
define class <object-declaration> (<value-declaration>)
  slot equated :: union(<string>, <false>), init-value: #f;
  slot read-only :: union(<boolean>, <empty-list>), init-value: #();
end class;  
define class <variable-declaration> (<object-declaration>)
  slot getter :: union(<string>, <false>), init-value: #f;
  slot setter :: union(<string>, <false>), init-value: #f;
end class;
define class <slot-declaration> (<object-declaration>)
  slot excluded? :: <boolean>, init-value: #f;
end class;
define class <result-declaration> (<object-declaration>) end class;
define class <arg-declaration> (<object-declaration>)
  slot direction :: <symbol>, init-value: #"default";
  slot original-type :: union(<false>, <type-declaration>),
    init-value: #f;
end class;
define class <varargs-declaration> (<arg-declaration>) end class;

// Given a function (or function type) declaration, locate the declaration
// corresponding to a given parameter, either by name or position.
//
define generic find-parameter (decl :: <declaration>, param :: <object>)
 => (result :: <arg-declaration>);

// Given a function (or function type) declaration, return the declaration
// corresponding to its result type.
//
define generic find-result (decl :: <declaration>) 
 => (result :: <result-declaration>);

// Flag a function result so that it will be ignored.
//
define generic ignored?-setter
    (value :: <boolean>, decl :: <result-declaration>) 
 => (result :: <boolean>);

// Sets the "direction" for the given argument and recomputes "type" and
// "original-type" if necessary.
//
define generic argument-direction-setter
    (dir :: <symbol>, decl :: <arg-declaration>) => (dir :: <symbol>);

define method equate (decl :: <object-declaration>, name :: <string>) => ();
  if (instance?(decl.type.true-type, <predefined-type-declaration>))
    error("Cannot 'equate:' predefined type: %s.", decl.type.simple-name);
  end if;
  decl.equated := name;
end method equate;

define method find-dylan-name
    (decl :: <function-declaration>, mapper :: <function>, prefix :: <string>,
     containers :: <sequence>, read-only :: <boolean>, sealing :: <string>)
 => (result :: <string>);
  find-dylan-name(decl.type, mapper, prefix, #(), read-only, sealing);
  decl.d-name
    | (decl.d-name := compute-dylan-name(decl, mapper, prefix, containers,
					 read-only, sealing));
end method find-dylan-name;

define method compute-dylan-name
    (decl :: <function-declaration>, mapper :: <function>, prefix :: <string>,
     containers :: <sequence>, rd-only :: <boolean>, sealing :: <string>)
 => (result :: <string>);
  find-dylan-name(decl.type, mapper, prefix, containers, rd-only, sealing);
  mapper(#"function", prefix, decl.simple-name, containers);
end method compute-dylan-name;

define method compute-closure 
    (results :: <deque>, decl :: <function-declaration>)
 => (results :: <deque>);
  if (~decl.declared?)
    decl.declared? := #t;

    // Don't declare the function type -- just do its parameters.
    compute-closure(results, decl.type.result);
    for (elem in decl.type.parameters)
      if (~instance?(elem, <varargs-declaration>))
	compute-closure(results, elem)
      end if; 
    end for;

    push-last(results, decl);
  end if;
  results;
end method compute-closure;

define method mapped-name
    (decl :: <object-declaration>, #key explicit-only?)
 => (result :: union(<string>, <false>));
  decl.map-type | mapped-name(decl.type, explicit-only?: #t) | decl.type-name;
end method mapped-name;

define method type-name (decl :: <object-declaration>) => (result :: <string>);
  decl.equated | decl.type.dylan-name;
end method type-name;

define method find-dylan-name
    (decl :: <value-declaration>, mapper :: <function>, prefix :: <string>,
     containers :: <sequence>, read-only :: <boolean>, sealing :: <string>)
 => (result :: <string>);
  if (decl.sealed-string = "") decl.sealed-string := sealing end if;
  decl.d-name
    | (decl.d-name := compute-dylan-name(decl, mapper, prefix, containers,
					 read-only, sealing));
end method find-dylan-name;

define method find-dylan-name
    (decl :: <object-declaration>, mapper :: <function>, prefix :: <string>,
     containers :: <sequence>, rd-only :: <boolean>, sealing :: <string>)
 => (result :: <string>);
  if (decl.sealed-string = "") decl.sealed-string := sealing end if;
  if (decl.read-only == #()) decl.read-only := rd-only end if;
  decl.d-name
    | (decl.d-name := compute-dylan-name(decl, mapper, prefix, containers,
					 rd-only, sealing));
end method find-dylan-name;

define method compute-dylan-name
    (decl :: <object-declaration>, mapper :: <function>, prefix :: <string>,
     containers :: <sequence>, rd-only :: <boolean>, sealing :: <string>)
 => (result :: <string>);
  mapper(#"variable", prefix, decl.simple-name, containers);
end method compute-dylan-name;

define method find-dylan-name
    (decl :: <variable-declaration>, mapper :: <function>, prefix :: <string>,
     containers :: <sequence>, rd-only :: <boolean>, sealing :: <string>)
 => (result :: <string>);
  if (decl.sealed-string = "") decl.sealed-string := sealing end if;
  if (decl.read-only == #()) decl.read-only := rd-only end if;
  decl.d-name
    | (decl.d-name := compute-dylan-name(decl, mapper, prefix, containers,
					 rd-only, sealing));
  decl.getter := decl.getter | decl.d-name;
  decl.setter := decl.setter | concatenate(decl.d-name, "-setter");
end method find-dylan-name;

define method compute-closure 
    (results :: <deque>, decl :: <object-declaration>) => (results :: <deque>);
  if (~decl.declared?)
    decl.declared? := #t;
    compute-closure(results, decl.type);
    push-last(results, decl);
  end if;
  results;
end method compute-closure;

define method find-dylan-name
    (decl :: <arg-declaration>, mapper :: <function>, prefix :: <string>,
     containers :: <sequence>, rd-only :: <boolean>, sealing :: <string>,
     #next next-method)
 => (result :: <string>);
  if (decl.original-type)
    find-dylan-name(decl.original-type, mapper, prefix, #(), rd-only,
		    sealing);
  end if;
  next-method();
end method find-dylan-name;

define method compute-dylan-name
    (decl :: <arg-declaration>, mapper :: <function>, prefix :: <string>,
     containers :: <sequence>, rd-only :: <boolean>, sealing :: <string>)
 => (result :: <string>);
  mapper(#"variable", prefix, decl.simple-name, containers);
end method compute-dylan-name;

define method compute-closure 
    (results :: <deque>, decl :: <result-declaration>)
 => (results :: <deque>);
  // We don't want to declare the args themselves, but we should make sure we
  // have the arg types.
  compute-closure(results, decl.type);
end method compute-closure;

define method compute-closure 
    (results :: <deque>, decl :: <arg-declaration>)
 => (results :: <deque>);
  // We don't want to declare the args themselves, but we should make sure we
  // have the arg types.
  if (decl.original-type)
    compute-closure(results, decl.original-type);
  end if;
  compute-closure(results, decl.type);
end method compute-closure;

define method find-parameter
    (decl :: <function-declaration>, param :: <object>)
 => (result :: <arg-declaration>);
  find-parameter(decl.type, param);
end method find-parameter;
  
define method find-parameter
    (decl :: <function-type-declaration>, param :: <integer>)
 => (result :: <arg-declaration>);
  element(decl.parameters, param - 1, default: #f)
    | error("No such parameter: %d.", param);
end method find-parameter;
  
define method find-parameter
    (decl :: <function-declaration>, param :: <string>)
 => (result :: <arg-declaration>);
  any?(method (arg) arg.simple-name = param & arg end method, decl.parameters)
    | error("No such parameter: %s.", param);
end method find-parameter;

define method find-parameter
    (decl :: <function-declaration>, param :: <symbol>)
 => (result :: <arg-declaration>);
  error("Cannot currently identify parameters by symbols.");
end method find-parameter;

define method find-result
    (decl :: <function-declaration>) => (result :: <result-declaration>);
  find-result(decl.type);
end method find-result;
  
define method find-result
    (decl :: <function-type-declaration>) => (result :: <result-declaration>);
  decl.result;
end method find-result;
  
define method ignored?-setter (value == #t, decl :: <result-declaration>)
 => (result :: <boolean>);
  decl.type := void-type;
  #t;
end method ignored?-setter;

define method argument-direction-setter
    (dir :: <symbol>, decl :: <arg-declaration>) => (dir :: <symbol>);
  if (decl.direction ~= #"default")
    error("Parameter direction cannot be respecified.");
  end if;
  if (dir ~= #"in")
    if (~instance?(decl.type.true-type, <pointer-declaration>))
      error("'Out' parameter is not an instance of a pointer type.");
    end if;
    decl.original-type := decl.type;
    decl.type := decl.type.true-type.referent;
  end if;
  decl.direction := dir;
end method argument-direction-setter;

//------------------------------------------------------------------------

define abstract class <constant-declaration> (<declaration>)
  slot constant-value :: <object>, required-init-keyword: #"value";
end class;
define class <enum-slot-declaration> (<constant-declaration>) end class;

define class <macro-declaration> (<constant-declaration>) end class;

// Attempts to add a new declarations corresponding to a CPP macro.  The value
// may be another declaration; or a constant value; or it may be
// indeterminate, in which case no declaration will be added.
//
define generic add-cpp-declaration
    (state :: <parse-state>, macro-name :: <string>) => ();

define method compute-dylan-name
    (decl :: <constant-declaration>, mapper :: <function>, prefix :: <string>,
     containers :: <sequence>, rd-only :: <boolean>, sealing :: <string>)
 => (result :: <string>);
  mapper(#"constant", prefix, decl.simple-name, containers);
end method compute-dylan-name;

define method add-cpp-declaration
    (state :: <parse-state>, macro-name :: <string>) => ();
  block ()
    let value = parse-macro(macro-name, state);
    state.objects[macro-name] :=
      add-declaration(state, make(<macro-declaration>, name: macro-name,
				  value: value));
  exception <error>
    #f;
  end block;
end method add-cpp-declaration;

define method compute-closure 
    (results :: <deque>, decl :: <macro-declaration>) => (results :: <deque>);
  if (~decl.declared?)
    decl.declared? := #t;
    if (instance?(decl.constant-value, <declaration>))
      compute-closure(results, decl.constant-value);
    end if;
    push-last(results, decl);
  end if;
  results;
end method compute-closure;

define method compute-dylan-name
    (decl :: <macro-declaration>, mapper :: <function>, prefix :: <string>,
     containers :: <sequence>, rd-only :: <boolean>, sealing :: <string>)
 => (result :: <string>);
  // If we are aliasing another declaration, we should use the same category.
  // We should only use #"constant" if we are renaming a constant or have an
  // actual constant value
  let category = select (decl.constant-value by instance?)
		   <constant-declaration> => #"constant";
		   <type-declaration> => #"type";
		   <value-declaration> => #"variable";
		   otherwise => #"constant";
		 end select;
  mapper(category, prefix, decl.simple-name, containers);
end method compute-dylan-name;
