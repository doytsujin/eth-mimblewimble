FROM zokrates/zokrates
MAINTAINER Wanseob Lim <email@wanseob.com>
COPY ./ ./
ENV args 0
RUN ./zokrates compile -i circuits/transaction.code
RUN ./zokrates setup
CMD ./zokrates compute-witness -a ${args} >/dev/null; ./zokrates generate-proof >/dev/null; sed -i -e '$a\' proof.json; cat proof.json;
