port module Main exposing (main)

import Platform


type alias Flags =
    { arguments : List String }


type alias Model =
    ()


type Msg
    = SshflingFinished Int


port requestSshfling : List String -> Cmd msg


port sshflingResult : (Int -> msg) -> Sub msg


port completed : Int -> Cmd msg


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( (), requestSshfling flags.arguments )


update : Msg -> Model -> ( Model, Cmd Msg )
update message model =
    case message of
        SshflingFinished exitCode ->
            ( model, completed exitCode )


subscriptions : Model -> Sub Msg
subscriptions _ =
    sshflingResult SshflingFinished


main : Program Flags Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }
