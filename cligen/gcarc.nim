when not declared(move):                # Temporary until support for old Nim
  template move*(x: auto): auto = x     #..versions is dropped.
