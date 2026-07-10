:- module(sshfling, [run/2, runtime_path/1, template_directory/1]).

:- use_module(library(error)).
:- use_module(library(process)).

:- dynamic module_directory/1.
:- prolog_load_context(directory, Directory),
   asserta(module_directory(Directory)).

environment_or_default(Name, Default, Value) :-
    ( getenv(Name, Configured),
      Configured \== ''
    -> Value = Configured
    ;  Value = Default
    ).

package_root(Root) :-
    ( getenv('SSHFLING_PACKAGE_ROOT', Configured),
      Configured \== ''
    -> Root = Configured
    ;  module_directory(ModuleDirectory),
       directory_file_path(ModuleDirectory, '..', Parent),
       absolute_file_name(Parent, Root, [file_type(directory), access(read)])
    ).

runtime_path(Path) :-
    ( getenv('SSHFLING_RUNTIME', Configured),
      Configured \== ''
    -> Path = Configured
    ;  package_root(Root),
       directory_file_path(Root, 'runtime/sshfling.py', Path)
    ).

template_directory(Path) :-
    ( getenv('SSHFLING_TEMPLATE_DIR', Configured),
      Configured \== ''
    -> Path = Configured
    ;  package_root(Root),
       directory_file_path(Root, 'runtime/templates', Path)
    ).

python_spec(Python, Spec) :-
    ( sub_atom(Python, _, _, _, '/')
    ; sub_atom(Python, _, _, _, '\\')
    ),
    !,
    Spec = Python.
python_spec(Python, path(Python)).

process_status(exit(Code), Code).
process_status(killed(Signal), Code) :-
    Code is 128 + Signal.

text_argument(Value, Text) :-
    ( string(Value)
    -> Text = Value
    ; atom(Value)
    -> atom_string(Value, Text)
    ; type_error(text, Value)
    ).

run(Arguments, Status) :-
    must_be(list, Arguments),
    maplist(text_argument, Arguments, NormalizedArguments),
    environment_or_default('SSHFLING_PYTHON', python3, Python),
    runtime_path(Runtime),
    template_directory(Templates),
    ( exists_file(Runtime)
    -> python_spec(Python, Executable),
       catch(
           ( process_create(
                 Executable,
                 [Runtime|NormalizedArguments],
                 [ process(Pid),
                   stdin(std),
                   stdout(std),
                   stderr(std),
                   environment(['SSHFLING_TEMPLATE_DIR'=Templates,
                                'PYTHONUNBUFFERED'='1'])
                 ]),
             process_wait(Pid, ProcessStatus),
             process_status(ProcessStatus, Status)
           ),
           error(existence_error(source_sink, _), _),
           Status = 127
       )
    ; Status = 127
    ).
