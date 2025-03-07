import { AO } from "wao"

const jwk = JSON.parse(readFileSync("../.aos.json").toString());
const ao = await new AO().init(jwk)

