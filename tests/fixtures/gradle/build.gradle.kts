tasks.register("printVersion") {
    val version = project.version
    doLast { println(version) }
}
