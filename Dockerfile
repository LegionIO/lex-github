FROM legionio/legion

COPY . /usr/src/app/lex-github

WORKDIR /usr/src/app/lex-github
RUN bundle install
