// Inicializacao idempotente do MongoDB do orchestrator.
//
// Executado pelo Job <name>-init (modules/mongodb/main.tf), autenticado como
// root. Pode rodar quantas vezes for preciso:
//   1. rs.initiate() so se o replica set ainda nao existir, com o host DNS
//      estavel do pod (<sts>-0.<svc>.<ns>.svc.cluster.local);
//   2. espera o no virar PRIMARY;
//   3. cria o usuario do orchestrator (readWrite no banco dele) ou, se ja
//      existir, atualiza senha e roles.

const host = process.env.MONGODB_HOST;
const port = process.env.MONGODB_PORT;
const replicaSet = process.env.MONGODB_REPLICA_SET;
const database = process.env.MONGODB_DATABASE;
const appUser = process.env.MONGODB_APP_USERNAME;
const appPassword = process.env.MONGODB_APP_PASSWORD;

// ── Replica set ──────────────────────────────────────────────────────────────
let initiated = true;
try {
  rs.status();
} catch (e) {
  // NotYetInitialized (94): primeira subida, ou volume emptyDir recriado.
  if (e.code !== 94 && e.codeName !== 'NotYetInitialized') {
    throw e;
  }
  initiated = false;
}

if (!initiated) {
  print(`Iniciando o replica set ${replicaSet} com ${host}:${port}`);
  rs.initiate({ _id: replicaSet, members: [{ _id: 0, host: `${host}:${port}` }] });
} else {
  print(`Replica set ${replicaSet} ja iniciado.`);
}

const deadline = Date.now() + 5 * 60 * 1000;
while (!db.hello().isWritablePrimary) {
  if (Date.now() > deadline) {
    throw new Error(`O no nao virou PRIMARY em 5 minutos: ${tojson(rs.status())}`);
  }
  print('Aguardando PRIMARY...');
  sleep(2000);
}
print('No PRIMARY.');

// ── Usuario do orchestrator ──────────────────────────────────────────────────
// Criado no proprio banco da aplicacao (authSource = database), com readWrite
// apenas nele.
const appDb = db.getSiblingDB(database);
const roles = [{ role: 'readWrite', db: database }];
const writeConcern = { w: 'majority' };

if (appDb.getUser(appUser)) {
  appDb.updateUser(appUser, { pwd: appPassword, roles: roles }, writeConcern);
  print(`Usuario ${appUser} ja existia — senha e roles atualizadas.`);
} else {
  appDb.createUser({ user: appUser, pwd: appPassword, roles: roles }, writeConcern);
  print(`Usuario ${appUser} criado em ${database}.`);
}
