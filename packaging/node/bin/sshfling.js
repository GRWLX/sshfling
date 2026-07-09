#!/usr/bin/env node
"use strict";

const { run } = require("../index.js");

process.exitCode = run(process.argv.slice(2));
