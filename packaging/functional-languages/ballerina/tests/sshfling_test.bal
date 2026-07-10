import ballerina/test;

@test:Config {}
function consumerRunsBundledCli() {
    test:assertEquals(run(["--version"]), 0);
}
