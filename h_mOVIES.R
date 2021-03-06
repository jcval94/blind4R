#https://www.youtube.com/watch?v=yFRSTlk3kRQ

#Hrrm movies pred
horror_movies <- readr::read_csv("https://raw.githubusercontent.com/rfordatascience/tidytuesday/master/data/2019/2019-10-22/horror_movies.csv")

library(tidyverse)
horror_movies

#Mejores pelis

HM_1<-horror_movies %>% arrange(desc(review_rating)) %>%
  extract(title,"anio","\\((\\d\\d\\d\\d)\\)",remove=F,convert = T)

HM_1$budget<-parse_number(HM_1$budget)

HM_1 %>% ggplot(aes(anio))+geom_histogram()

#La mayoría de las pelis están depués de 2010

HM_1 %>% count(genres,sort = T)

HM_1 %>% count(language,sort = T)

#Retiramos el formato
HM_1 %>% count(budget,sort = T) %>%
  ggplot(aes(budget))+geom_histogram()+
  scale_x_log10(labels=scales::dollar)

#Peliculas con más presupuesto tienen mejor rating?


HM_1 %>% ggplot(aes(budget,review_rating)) +
  geom_point() + scale_x_log10(labels=scales::dollar)+
  geom_smooth(method = "glm")
#No parece haber una correlaci{on}

HM_1 %>% select(budget,review_rating) %>% 
  filter(!is.na(budget) & !is.na(review_rating)) %>%
  cor()
#En efecto, es muy baja la correlaci{on}

HM_1 %>% mutate(movie_rating=fct_lump(movie_rating,5)) %>%
  count(movie_rating,sort = T) %>% 
  ggplot(aes(reorder(movie_rating,n),n)) +
  geom_col()+coord_flip()

#Veremos la variaci{on de los reviews respecto a la clasificacion
#de la pelicula
HM_1 %>% mutate(movie_rating=fct_lump(movie_rating,5)) %>%
  ggplot(aes(reorder(movie_rating,review_rating),review_rating)) +
  geom_boxplot()+coord_flip()

#Analizaremos la varianza

#Primero debemos revisar si la dist. es normal
library(FitUltD)
Fit<-FDist(na.omit(HM_1$review_rating),plot = T)
Fit[[4]]
#Efectivamente, p.valores >0.05, ahora podemos utilizar anova()

#Retiramos na's
HM_1 %>% mutate(movie_rating=fct_lump(movie_rating,5)) %>%
  filter(!is.na(movie_rating)) %>%
  lm(review_rating~movie_rating,data=.) %>%
  anova()
  
#Dado que Pr(>F) (p.valor) es muy cercano a 0 entonces rechazamos que
#tienen la misma varianza, es decir, el tipo de pel{icula} afecta la calificación


#Analisis de columnas con "|" como separador 
#(aquellas con más d euna clasificación)
HM_1 %>% filter(!is.na(genres)) %>% 
  separate_rows(genres,sep = "\\| ") %>%
  mutate(genres=fct_lump(genres,5)) %>%
  ggplot(aes(reorder(genres,review_rating),review_rating)) +
  geom_boxplot()+coord_flip()


HM_1 %>% filter(!is.na(genres)) %>% 
  separate_rows(genres,sep = "\\| ") %>%
  mutate(genres=fct_lump(genres,5)) %>% 
  lm(review_rating~genres,data = .) %>%
  anova()

#mismo resultado para el g{enero}

#Ahora separaremos la columna plot
HM_2 <- HM_1 %>% 
  separate(plot,into=c("Director","cast","plot"),sep="\\.")


HM_2$Director<-HM_2$Director %>% str_remove("Directed by ")
HM_2$cast<-HM_2$cast %>% str_remove(" With ")

library(tidytext)

words<-HM_2 %>% 
  select(title,plot,review_rating,movie_rating) %>% 
  unnest_tokens(word,plot) %>%
  anti_join(stop_words,by="word")

words %>% count(word,sort = T) %>% 
  head(15) %>% ggplot(aes(reorder(word,n),n)) +
  geom_col()+coord_flip()

#estadísticos por palabra
W_RT<-words %>% filter(!is.na(review_rating)) %>% 
  group_by(word) %>%
  summarize(pelis=n(),rating=mean(review_rating)) %>%
  arrange(desc(pelis))


W_RT %>% filter(pelis>=75 & rating>4) %>%
  ggplot(aes(reorder(word,rating),rating))+geom_point()+coord_flip()

#Por lo visto las mujeres mejoran el rating de una peli de terror
#Probémoslo...

##Hagamos regresión Lasso
library(glmnet)
#Hagamos una matriz de las películas y las palabras que más aparecen en ellas
Matriz_palabras<-words %>% 
  filter(!is.na(review_rating))%>% 
  add_count(word) %>% filter(n>=20) %>%
  count(title,word) %>% cast_sparse(title,word,n)

# El cast_sparse hace la función inversa de count con 2 o más variables
# es decir, transforma dos columnas en un data frame
####-----------
#EJEMPLO
dat <- data.frame(a = c("row1", "row1", "row2", "row2", "row2"),
                  b = c("col1", "col2", "col1", "col3", "col4"),
                  val = 1:5)

cast_sparse(dat, a, b)
cast_sparse(dat, a, b, val)
####-----------



y<-words$review_rating[match(rownames(Matriz_palabras),words$title)]

qplot(y)

#La funciñon cv.glmnet hace cross validation para un 
#modelo lineal simple para Regularization, que calcula el 
#valor de lambda para aplicar como penalizaci{on de un modelo
#lineal y=a+b*x+lambda*abs(b)
#que sirve para mejorar la predicción de la matriz
#respecto al valor que queremos calcular

View(Matriz_palabras)
Matriz_palabras@Dim
#Son 2420 filas y 240 columnas con valores igual a la
#cantidad de veces que se repiten los valores

lasso_model<-cv.glmnet(Matriz_palabras,y)

library(broom)
#Matriz_palabras %>% ggplot(aes())
lasso<-tidy(lasso_model$glmnet.fit)

plot(lasso_model)

#Vemos que entre más crece lambda más disminuye el error 
#hasta llegar el valor log(lambda)=-3
#Es decir, ente más se reduce la penalización
#el error disminuye y entonces, un modelo lineal estaría
#bastante sobreajustado

#Veamos como cambian los parámetros
#(pendientes) de las regresiones
#conforme lambda avanza
#y en qué punto se ve la mejor pendiente
lasso[lasso$term %in% c("quickly","seek","evil","unespected",
                        "village","collage",
                         "friends","army","teacher","boy"),] %>%
  ggplot(aes(x = lambda,y = estimate,color=term))+
  geom_line()+
  scale_x_log10()+
  geom_vline(xintercept = lasso_model$lambda.min)+
  geom_hline(yintercept = 0,lty=2)

#El valor de lambda que minimiza el error es:
lasso_model$lambda.min

#Ahora veamos las pendientes
#más altas y las menores y qué variables están asociadas
#a estas
lasso[lasso$lambda==lasso_model$lambda.min &
        lasso$term!="(Intercept)",] %>%
  ggplot(aes(reorder(term,estimate),estimate)) +
  geom_col() +
  coord_flip()



